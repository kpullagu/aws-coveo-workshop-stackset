import asyncio
import json
import logging
import threading
import typing as t
from contextlib import asynccontextmanager
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

from mcp.client.session import ClientSession
from mcp.client.streamable_http import streamablehttp_client

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)


class MCPToolError(Exception):
    """Raised when the Hosted MCP server returns isError=True."""

    def __init__(self, tool_name: str, message: str) -> None:
        self.tool_name = tool_name
        super().__init__(message)


TOOL_KEY_TO_CONTROL_KEY = {
    "answer_tool": "answer",
    "fetch_tool": "fetch",
    "passage_tool": "passages",
    "search_tool": "search",
}


class CoveoMCPAdapter:
    def __init__(
        self,
        endpoint: str,
        auth_mode: str = "anonymous_api_key",
        api_key: t.Optional[str] = None,
        region: t.Optional[str] = None,
        sse_read_timeout: int = 300,
        request_timeout: int = 120,
    ) -> None:
        if not endpoint:
            raise ValueError("Hosted MCP endpoint is required")

        self.endpoint = endpoint
        self.auth_mode = auth_mode
        self.api_key = api_key
        self.region = region or "us-east-1"
        self._sse_read_timeout = int(sse_read_timeout)
        self._request_timeout = int(request_timeout)
        self._session_id: t.Optional[str] = None
        self._controls: dict = {}
        self._tool_schemas: dict[str, dict] = {}
        self._tool_schema_lock = threading.Lock()

    def set_session_id(self, session_id: str) -> None:
        self._session_id = session_id

    def set_controls(self, controls: t.Optional[dict] = None) -> None:
        self._controls = controls or {}

    def get_extra(self, tool_name: str) -> dict:
        control_key = TOOL_KEY_TO_CONTROL_KEY.get(tool_name, tool_name)
        value = self._controls.get(control_key)
        return value if isinstance(value, dict) else {}

    def _build_endpoint_url(self) -> str:
        if self.auth_mode != "anonymous_api_key":
            raise ValueError(f"Unsupported Hosted MCP auth mode: {self.auth_mode}")
        if not self.api_key:
            raise ValueError("Hosted MCP API key is required for anonymous_api_key mode")

        parsed = urlparse(self.endpoint)
        query_pairs = dict(parse_qsl(parsed.query, keep_blank_values=True))
        query_pairs["access_token"] = self.api_key
        return urlunparse(parsed._replace(query=urlencode(query_pairs)))

    def _safe_endpoint_for_logs(self) -> str:
        parsed = urlparse(self._build_endpoint_url())
        query_pairs = dict(parse_qsl(parsed.query, keep_blank_values=True))
        if "access_token" in query_pairs:
            query_pairs["access_token"] = f"{query_pairs['access_token'][:10]}..."
        return urlunparse(parsed._replace(query=urlencode(query_pairs)))

    @asynccontextmanager
    async def _session(self):
        url = self._build_endpoint_url()
        logger.debug("Hosted MCP URL=%s", self._safe_endpoint_for_logs())

        async with streamablehttp_client(
            url=url,
            timeout=self._request_timeout,
            sse_read_timeout=self._sse_read_timeout,
            terminate_on_close=False,
        ) as (read_stream, write_stream, _get_session_id):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                yield session

    def _json_safe(self, value: t.Any) -> t.Any:
        if value is None or isinstance(value, (str, int, float, bool)):
            return value
        if isinstance(value, list):
            return [self._json_safe(item) for item in value]
        if isinstance(value, tuple):
            return [self._json_safe(item) for item in value]
        if isinstance(value, dict):
            return {str(key): self._json_safe(item) for key, item in value.items() if not callable(item)}
        if hasattr(value, "model_dump") and callable(value.model_dump):
            return self._json_safe(value.model_dump())
        if hasattr(value, "dict") and callable(value.dict):
            return self._json_safe(value.dict())
        return str(value)

    def _extract_content_payload(self, item: t.Any) -> tuple[bool, t.Any]:
        for attr in ("structuredContent", "structured_content", "data"):
            value = getattr(item, attr, None)
            if value is not None and not callable(value):
                return True, self._json_safe(value)

        text_value = getattr(item, "text", None)
        if text_value:
            try:
                return True, self._json_safe(json.loads(text_value))
            except json.JSONDecodeError:
                return False, text_value

        if isinstance(item, (dict, list, tuple)):
            return True, self._json_safe(item)

        return True, self._json_safe(item)

    def _normalize_content(self, result: t.Any) -> t.Any:
        payloads: list[t.Any] = []
        text_parts: list[str] = []

        for item in getattr(result, "content", []) or []:
            is_payload, value = self._extract_content_payload(item)
            if is_payload:
                payloads.append(value)
            elif value:
                text_parts.append(str(value))

        if len(payloads) == 1:
            return payloads[0]
        if payloads:
            return {"items": payloads, "text": "\n".join(text_parts) if text_parts else ""}
        return {"text": "\n".join(text_parts)} if text_parts else {}

    def _extract_tool_schemas(self, tool_result: t.Any) -> dict[str, dict]:
        tools = getattr(tool_result, "tools", None) or []
        schemas: dict[str, dict] = {}
        names: list[str] = []

        for tool in tools:
            name = getattr(tool, "name", None)
            if not name:
                continue
            names.append(name)
            schemas[name] = {
                "description": getattr(tool, "description", "") or "",
                "inputSchema": getattr(tool, "inputSchema", None) or getattr(tool, "input_schema", None) or {},
            }

        logger.info("Discovered Hosted MCP tools: %s", ", ".join(names))
        return schemas

    async def _discover_tools_async(self) -> dict[str, dict]:
        async with self._session() as session:
            tool_result = await session.list_tools()
            return self._extract_tool_schemas(tool_result)

    def _run_async(self, coro: t.Coroutine[t.Any, t.Any, t.Any]) -> t.Any:
        container: dict[str, t.Any] = {}
        exception_container: dict[str, Exception] = {}

        def _runner() -> None:
            loop = asyncio.new_event_loop()
            try:
                asyncio.set_event_loop(loop)
                container["result"] = loop.run_until_complete(coro)
            except Exception as exc:
                exception_container["error"] = exc
            finally:
                loop.close()

        thread = threading.Thread(target=_runner, daemon=False)
        thread.start()
        thread.join(timeout=self._request_timeout + 10)

        if thread.is_alive():
            raise TimeoutError("Timed out waiting for Hosted MCP response")
        if "error" in exception_container:
            raise exception_container["error"]
        return container.get("result")

    def _ensure_tool_schemas(self) -> dict[str, dict]:
        with self._tool_schema_lock:
            if not self._tool_schemas:
                self._tool_schemas = self._run_async(self._discover_tools_async())
        return self._tool_schemas

    def discover_tools(self) -> dict[str, dict]:
        return self._ensure_tool_schemas()

    @staticmethod
    def _pick_schema_key(properties: dict, *candidates: str) -> t.Optional[str]:
        lower_map = {key.lower(): key for key in properties.keys()}
        for candidate in candidates:
            if candidate.lower() in lower_map:
                return lower_map[candidate.lower()]
        return None

    def _translate_arguments(self, tool_name: str, arguments: dict[str, t.Any]) -> dict[str, t.Any]:
        schemas = self._ensure_tool_schemas()
        schema = schemas.get(tool_name, {}).get("inputSchema", {})
        properties = schema.get("properties", {}) if isinstance(schema, dict) else {}
        if not properties:
            return arguments

        translated = dict(arguments)
        query_key = self._pick_schema_key(properties, "query", "q", "question")
        top_k_key = self._pick_schema_key(
            properties,
            "top_k",
            "topK",
            "k",
            "numberOfResults",
            "numberOfPassages",
            "count",
            "limit",
            "pageSize",
        )
        filter_key = self._pick_schema_key(properties, "filters", "filter")
        answer_config_key = self._pick_schema_key(properties, "answer_config_id", "answerConfigId", "answerConfigurationId")
        item_key = self._pick_schema_key(
            properties,
            "item_id",
            "id",
            "documentId",
            "permanentid",
            "permanentId",
            "uniqueid",
            "uniqueId",
            "uri",
        )

        if "query" in translated and query_key and query_key != "query":
            translated[query_key] = translated.pop("query")
        elif "query" in translated and not query_key and len(properties) == 1:
            only_key = next(iter(properties))
            translated[only_key] = translated.pop("query")

        if "top_k" in translated:
            if top_k_key and top_k_key != "top_k":
                translated[top_k_key] = translated.pop("top_k")
            elif "top_k" not in properties:
                translated.pop("top_k")

        if "filters" in translated:
            if filter_key and filter_key != "filters":
                translated[filter_key] = translated.pop("filters")
            elif "filters" not in properties:
                translated.pop("filters")

        if "answer_config_id" in translated:
            if answer_config_key and answer_config_key != "answer_config_id":
                translated[answer_config_key] = translated.pop("answer_config_id")
            elif "answer_config_id" not in properties:
                translated.pop("answer_config_id")

        if "item_id" in translated:
            if item_key and item_key != "item_id":
                translated[item_key] = translated.pop("item_id")
            elif not item_key and len(properties) == 1:
                only_key = next(iter(properties))
                translated[only_key] = translated.pop("item_id")
            elif "item_id" not in properties:
                translated.pop("item_id")

        allowed_keys = set(properties.keys())
        return {key: value for key, value in translated.items() if key in allowed_keys}

    async def _call_tool_async(self, name: str, arguments: dict[str, t.Any]) -> t.Any:
        logger.debug("Hosted MCP call: tool=%s arguments=%s", name, arguments)

        if self._session_id:
            print(f"OBSERVABILITY session_id={self._session_id} event=mcp_tool_call tool={name}")

        translated_arguments = self._translate_arguments(name, arguments)
        logger.debug("Hosted MCP translated args: tool=%s arguments=%s", name, translated_arguments)

        try:
            async with self._session() as session:
                result = await session.call_tool(name, translated_arguments)

                is_error = getattr(result, "isError", False) or getattr(result, "is_error", False)
                if is_error:
                    error_text = ""
                    for item in getattr(result, "content", []) or []:
                        text_value = getattr(item, "text", None)
                        if text_value:
                            error_text = text_value
                            break
                    if self._session_id:
                        print(
                            f"OBSERVABILITY session_id={self._session_id} event=mcp_tool_error "
                            f"tool={name} error=MCPToolError message={error_text[:200]}"
                        )
                    logger.error("Hosted MCP tool %s returned isError=True: %s", name, error_text)
                    raise MCPToolError(name, error_text or f"Tool {name} returned an error")

                if self._session_id:
                    print(f"OBSERVABILITY session_id={self._session_id} event=mcp_tool_success tool={name}")
                return self._normalize_content(result)
        except Exception as exc:
            if self._session_id:
                print(
                    f"OBSERVABILITY session_id={self._session_id} event=mcp_tool_error "
                    f"tool={name} error={type(exc).__name__}"
                )
            logger.error("Hosted MCP tool call failed for %s: %s", name, exc)
            raise

    def call_tool(self, name: str, arguments: dict[str, t.Any]) -> t.Any:
        return self._run_async(self._call_tool_async(name, arguments))
