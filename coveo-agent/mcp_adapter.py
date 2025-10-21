# coveo-agent/mcp_adapter.py
import os
import json
import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import timedelta
from typing import Any, Dict, Optional

import boto3
from mcp.client.session import ClientSession
from sigv4_transport import streamablehttp_client_with_sigv4

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)


class CoveoMCPAdapter:
    def __init__(
        self,
        mcp_runtime_arn: Optional[str] = None,
        region: Optional[str] = None,
        mcp_url: Optional[str] = None,
        sse_read_timeout: int = 300,
        request_timeout: int = 120,
    ) -> None:
        self.mcp_runtime_arn = mcp_runtime_arn or os.getenv("COVEO_MCP_RUNTIME_ARN")
        self.region = region or os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "us-east-1"
        self.mcp_url = mcp_url or os.getenv("COVEO_MCP_URL")
        self._sse_read_timeout = int(sse_read_timeout)
        self._request_timeout = int(request_timeout)

        # Get AWS credentials for SigV4 authentication
        session = boto3.Session()
        self._credentials = session.get_credentials()
    
    def set_controls(self, controls: Optional[Dict] = None):
        """Set controls for tool customization"""
        self._controls = controls or {}
    
    def get_extra(self, tool_key: str) -> Dict:
        """Get extra parameters for a specific tool"""
        value = getattr(self, '_controls', {}).get(tool_key)
        return value if isinstance(value, dict) else {}

    def _build_mcp_url(self) -> str:
        # https://bedrock-agentcore.<region>.amazonaws.com/runtimes/<encoded-arn>/invocations?qualifier=DEFAULT
        if not self.mcp_runtime_arn:
            raise ValueError("mcp_runtime_arn is required when mcp_url is not provided")
        import urllib.parse
        encoded = urllib.parse.quote(self.mcp_runtime_arn, safe="")
        return f"https://bedrock-agentcore.{self.region}.amazonaws.com/runtimes/{encoded}/invocations?qualifier=DEFAULT"

    @asynccontextmanager
    async def _session(self):
        """
        Open a temporary MCP session over Streamable HTTP with SigV4 authentication.
        Uses AWS SigV4 to authenticate with AgentCore runtime invocation API.
        """
        sse_read_timeout = self._sse_read_timeout
        req_timeout = self._request_timeout

        # Build URL (either explicit or from runtime ARN)
        url = self.mcp_url if self.mcp_url else self._build_mcp_url()
        
        logger.debug("MCP URL=%s", url)
        logger.debug("Using SigV4 authentication for AgentCore API")
        
        # Use SigV4 authentication for AgentCore runtime invocation API
        async with streamablehttp_client_with_sigv4(
            url=url,
            service="bedrock-agentcore",
            region=self.region,
            credentials=self._credentials,
            timeout=req_timeout,
            sse_read_timeout=sse_read_timeout,
            terminate_on_close=False,
        ) as (r, w, get_session_id):
            # ClientSession only accepts (read_stream, write_stream) - no other kwargs
            # The get_session_id callback is for reuse but not passed to ClientSession
            async with ClientSession(r, w) as session:
                await session.initialize()
                yield session

    async def _call_tool_async(self, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        logger.debug("DEBUG: _call_tool_async called: name=%s, arguments=%s", name, arguments)
        try:
            async with self._session() as session:
                result = await session.call_tool(name, arguments)
                # Normalize MCP result content to plain text (or JSON string) for the agent
                items = []
                for c in getattr(result, "content", []) or []:
                    if hasattr(c, "text") and c.text is not None:
                        items.append(c.text)
                    elif hasattr(c, "json") and c.json is not None:
                        items.append(json.dumps(c.json))
                    elif hasattr(c, "type") and c.type == "error":
                        items.append(f"Error: {getattr(c, 'error', 'unknown error')}")
                return {"content": "\n".join(items) if items else ""}
        except Exception as e:
            logger.error("ERROR: Exception in _call_tool_async for tool %s", name)
            logger.error("ERROR: Exception type: %s", type(e).__name__)
            logger.error("ERROR: Exception message: %s", str(e))
            raise

    def call_tool(self, name: str, arguments: Dict[str, Any]) -> str:
        """
        Sync wrapper called by the Bedrock Agent runtime tool layer.
        ALWAYS runs in a separate thread to avoid nested event loop issues.
        """
        logger.debug("DEBUG: call_tool (sync wrapper) called: name=%s", name)
        
        # ALWAYS use a separate thread with its own event loop
        # This avoids ExceptionGroup errors from nested event loops in AgentCore
        import threading
        
        container: Dict[str, Any] = {}
        exception_container: Dict[str, Any] = {}
        
        def _runner():
            loop = asyncio.new_event_loop()
            try:
                asyncio.set_event_loop(loop)
                container["result"] = loop.run_until_complete(self._call_tool_async(name, arguments))
            except Exception as e:
                exception_container["error"] = e
                logger.error("ERROR: Exception in thread runner for tool %s", name)
                logger.error("ERROR: Exception type: %s", type(e).__name__)
                logger.error("ERROR: Exception message: %s", str(e))
                import traceback
                logger.error("ERROR: Traceback:\n%s", traceback.format_exc())
            finally:
                loop.close()
        
        t = threading.Thread(target=_runner, daemon=False)
        t.start()
        t.join(timeout=self._request_timeout + 10)  # Add buffer to timeout
        
        if t.is_alive():
            logger.error("ERROR: Thread timeout for tool %s", name)
            return ""
        
        if "error" in exception_container:
            # Re-raise the exception from the thread
            raise exception_container["error"]
        
        return (container.get("result") or {}).get("content", "")
