# coveo-agent/sigv4_transport.py
import asyncio
import json
from contextlib import asynccontextmanager
from typing import Optional, Tuple, Callable, Any

import httpx
from mcp.client.streamable_http import streamablehttp_client, GetSessionIdCallback


class SigV4HTTPXAuth(httpx.Auth):
    """
    Minimal SigV4 auth for HTTPX. Assumes AWS credentials present in env/role.
    """
    requires_request_body = True

    def __init__(self, service: str, region: str):
        self._service = service
        self._region = region

    def auth_flow(self, request: httpx.Request):
        # Sign with botocore SigV4
        import botocore.auth
        import botocore.awsrequest
        import botocore.session

        session = botocore.session.get_session()
        creds = session.get_credentials()
        if creds is None:
            raise RuntimeError("No AWS credentials available for SigV4 signing")

        # Copy headers but exclude 'connection' - HTTPX mutates it after signing
        # which causes signature mismatch and 403 Forbidden
        signed_headers = dict(request.headers)
        signed_headers.pop("connection", None)
        signed_headers.pop("Connection", None)  # Case-insensitive check

        # Convert to AWSRequest
        aws_req = botocore.awsrequest.AWSRequest(
            method=request.method,
            url=str(request.url),
            data=request.content,
            headers=signed_headers,
        )

        signer = botocore.auth.SigV4Auth(creds, self._service, self._region)
        signer.add_auth(aws_req)
        # Copy back signed headers
        for k, v in aws_req.headers.items():
            request.headers[k.decode() if isinstance(k, bytes) else k] = v.decode() if isinstance(v, bytes) else v
        yield request


@asynccontextmanager
async def streamablehttp_client_with_sigv4(
    url: str,
    service: str = "bedrock-agentcore",  # <<< FIXED default
    region: Optional[str] = None,
    credentials: Any = None,             # not used; httpx+botocore looks up env/role
    timeout: int = 120,
    sse_read_timeout: int = 300,
    terminate_on_close: bool = False,
) -> Tuple[asyncio.StreamReader, asyncio.StreamWriter, GetSessionIdCallback]:
    """
    Wrap mcp.client.streamable_http.streamablehttp_client and apply SigV4 signing
    for the Bedrock AgentCore endpoint.
    """
    auth = SigV4HTTPXAuth(service=service, region=region or "us-east-1")
    async with streamablehttp_client(
        url=url,
        auth=auth,
        timeout=timeout,
        sse_read_timeout=sse_read_timeout,
        terminate_on_close=terminate_on_close,
    ) as (r, w, get_session_id):
        yield (r, w, get_session_id)
