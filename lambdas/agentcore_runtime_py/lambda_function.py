# lambda_function.py
"""
AgentCore Runtime Lambda with Bedrock AgentCore Client implementation.

This Lambda communicates with the Agent Runtime using the AWS Bedrock AgentCore service.
The Agent Runtime orchestrates tool calls to the MCP server.

Architecture:
    UI → API Gateway → Lambda (this file) → Agent Runtime → MCP Runtime → Coveo API

Flow:
    1. Lambda receives chat (or answer) request from API Gateway
    2. Lambda invokes the Agent runtime (one input: { text, controls? })
    3. Agent decides which MCP tools to call (answer/search/passages) and synthesizes the reply
    4. Lambda returns a normalized JSON to the UI/BFF

What changed (minimal):
    • Added `controls` pass-through so UI/BFF can request extra fields for Coveo tools
      e.g., controls.passages.additionalFields = ["title","clickableuri","project","uniqueid","summary"]
    • No tool-specific payloads in Lambda for coveoMCP — the Agent chooses the tool(s)
"""

import json
import logging
import os
import uuid
from typing import Dict, Any, Optional

# -------- X-Ray Tracing --------
try:
    from aws_xray_sdk.core import xray_recorder, patch_all
    patch_all()  # Instrument boto3/requests for tracing
    XRAY_AVAILABLE = True
except ImportError:
    XRAY_AVAILABLE = False
    logging.warning("X-Ray SDK not available, tracing disabled")

# -------- Logging --------
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Try to import boto3 for AgentCore and SSM
try:
    import boto3
    ssm_client = boto3.client('ssm')
    agentcore_client = boto3.client('bedrock-agentcore')
    HAS_BOTO3 = True
except ImportError:
    HAS_BOTO3 = False
    logger.warning("boto3 not available, cannot use AgentCore or SSM")

# Optional: requests + SigV4 (kept consistent with prior code patterns)
HAS_REQUESTS = False
requests = None
SigV4Auth = None
AWSRequest = None

try:
    import requests
    from botocore.auth import SigV4Auth
    from botocore.awsrequest import AWSRequest
    HAS_REQUESTS = True
except Exception as e:
    logger.warning("Requests/Botocore pieces not available: %s", str(e))


# ----------------------------
# AgentCore HTTPS client
# ----------------------------
class AgentCoreClient:
    """Client for communicating with Agent Runtime via HTTPS Invocation URL"""

    def __init__(self, runtime_arn: str, session_id: Optional[str] = None):
        if not HAS_BOTO3:
            raise Exception("boto3 is required for AgentCore client")

        self.runtime_arn = runtime_arn
        self.session_id = session_id or str(uuid.uuid4())

        # Build the invocation URL from runtime ARN
        # ARN format: arn:aws:bedrock-agentcore:region:account:runtime/runtime-id
        region = runtime_arn.split(':')[3]

        # URL encode the entire ARN
        import urllib.parse
        encoded_arn = urllib.parse.quote(runtime_arn, safe='')

        # Build invocation URL using encoded ARN
        self.invocation_url = (
            f"https://bedrock-agentcore.{region}.amazonaws.com/"
            f"runtimes/{encoded_arn}/invocations?qualifier=DEFAULT"
        )

        logger.info(
            f"Initialized AgentCore client for Agent runtime: {self.runtime_arn}, session: {self.session_id}"
        )
        logger.info(f"Invocation URL: {self.invocation_url}")

    def invoke_runtime(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Invoke Agent Runtime using HTTPS invocation URL with AWS SigV4 signing"""
        logger.debug(f"Invoking Agent runtime via HTTPS with payload: {payload}")

        try:
            headers = {
                'Content-Type': 'application/json',
                'Accept': 'application/json, text/event-stream',
                # Session header is how AgentCore keeps multi-turn continuity
                'X-Amzn-Bedrock-AgentCore-Runtime-Session-Id': self.session_id
            }

            body = json.dumps(payload)

            # Check if requests and signing are available
            if not HAS_REQUESTS or AWSRequest is None or SigV4Auth is None or requests is None:
                raise RuntimeError("requests library or botocore signing not available")

            # SigV4 sign the request
            credentials = boto3.Session().get_credentials()
            region = self.runtime_arn.split(':')[3]
            aws_req = AWSRequest(
                method='POST',
                url=self.invocation_url,
                data=body,
                headers=headers
            )
            SigV4Auth(credentials, 'bedrock-agentcore', region).add_auth(aws_req)

            response = requests.post(
                self.invocation_url,
                headers=dict(aws_req.headers),
                data=aws_req.data,
                timeout=90
            )

            logger.info(f"Agent runtime call status: {response.status_code}")

            if response.status_code != 200:
                raise Exception(f"HTTP {response.status_code}: {response.text}")

            content_type = response.headers.get('Content-Type', '')
            response_text = response.text

            # Parse response based on content type
            if 'application/json' in content_type:
                # Standard JSON response
                try:
                    return json.loads(response_text)
                except json.JSONDecodeError as e:
                    logger.error(f"Failed to parse JSON response: {e}")
                    logger.error(f"Response text: {response_text[:500]}")
                    return {"response": response_text}
            
            elif 'text/event-stream' in content_type or response_text.startswith('event:'):
                # SSE response - parse events
                logger.info("Parsing SSE response")
                lines = response_text.split('\n')
                for line in lines:
                    if line.startswith('data: '):
                        try:
                            return json.loads(line[6:])
                        except json.JSONDecodeError:
                            continue
                # If no valid JSON found in SSE, return raw text
                logger.warning("No valid JSON found in SSE response")
                return {"response": response_text}
            
            else:
                # Unknown content type - try to parse as JSON
                logger.warning(f"Unknown content type: {content_type}, attempting JSON parse")
                try:
                    return json.loads(response_text)
                except json.JSONDecodeError:
                    logger.warning("Failed to parse as JSON, returning raw text")
                    return {"response": response_text}

        except Exception as e:
            logger.error(f"Error invoking Agent Runtime: {e}")
            # If the exception carries a response, surface it
            if hasattr(e, 'response'):
                logger.error(f"Error response: {e.response}")
            raise

    def ask_agent(self, text: str, controls: Optional[Dict[str, Any]] = None, session_id: Optional[str] = None, actor_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Ask the Agent a question. The Agent will decide which MCP tools to call.
        Agent expects a simple payload: { "text": "...", "controls": {...}?, "session_id": "...", "actor_id": "..." }
        """
        payload = {"text": text}
        # Pass-through controls (e.g., for Coveo Passages additionalFields)
        if controls:
            payload["controls"] = controls
        # Pass session_id and actor_id for memory
        if session_id:
            payload["session_id"] = session_id
        if actor_id:
            payload["actor_id"] = actor_id
        return self.invoke_runtime(payload)

    def health_check(self) -> Dict[str, Any]:
        payload = {"text": "health check"}
        return self.invoke_runtime(payload)


# ----------------------------
# Helper: resolve Agent runtime ARN
# ----------------------------
def get_runtime_arn() -> str:
    """
    Get AgentCore Runtime ARN from environment variable or SSM Parameter Store.

    Priority:
    1. AGENTCORE_RUNTIME_ARN environment variable
    2. SSM Parameter: /${STACK_PREFIX}/coveo/runtime-arn
    3. Construct from runtime-id if available
    4. Raise exception if not found
    """
    runtime_arn = os.environ.get('AGENTCORE_RUNTIME_ARN', '')

    # If env var is not set, try SSM for ARN first
    if not runtime_arn and HAS_BOTO3:
        try:
            stack_prefix = os.environ.get('STACK_PREFIX', 'workshop')
            param_name = f'/{stack_prefix}/coveo/runtime-arn'
            response = ssm_client.get_parameter(Name=param_name)
            runtime_arn = response['Parameter']['Value']
            logger.info(f"Loaded runtime ARN from SSM: {param_name}")
        except Exception as e:
            logger.warning(f"Failed to load runtime ARN from SSM: {str(e)}")
            # Try to construct from runtime-id
            try:
                param_name = f'/{stack_prefix}/coveo/runtime-id'
                response = ssm_client.get_parameter(Name=param_name)
                runtime_id = response['Parameter']['Value']

                sts_client = boto3.client('sts')
                account_id = sts_client.get_caller_identity()['Account']
                region = agentcore_client.meta.region_name
                runtime_arn = f"arn:aws:bedrock-agentcore:{region}:{account_id}:runtime/{runtime_id}"

                logger.info(f"Constructed runtime ARN from ID: {runtime_arn}")
            except Exception as e2:
                logger.warning(f"Failed to construct runtime ARN: {str(e2)}")

    if not runtime_arn:
        raise ValueError("AgentCore Runtime ARN not configured")

    return runtime_arn


# ----------------------------
# Request handlers
# ----------------------------
def handle_chat_request(request_data: Dict[str, Any], runtime_arn: str) -> Dict[str, Any]:
    """
    Handle chat/answer requests by communicating with Agent Runtime.

    With backend=coveoMCP, we don't craft tool-specific payloads here.
    We pass the user message + optional 'controls' and let the Agent choose tools.
    """
    try:
        # Extract chat parameters
        question = request_data.get('question', '') or request_data.get('query', '') or request_data.get('text', '')
        session_id = request_data.get('sessionId', str(uuid.uuid4()))
        backend = request_data.get('backend', request_data.get('backendMode', 'coveoMCP'))
        conversation_type = request_data.get('conversationType', 'multi-turn')

        # NEW: controls pass-through (e.g., passages.additionalFields)
        controls = request_data.get('controls')

        if not question:
            return create_error_response(400, "Question is required")

        logger.info(f"Processing answer/chat request (backend={backend}, type={conversation_type})")

        # Build a minimal prompt for single-turn, otherwise use the raw question
        if conversation_type == 'single-turn':
            prompt = f"Answer this question concisely: {question}"
        else:
            prompt = question

        logger.info(f"Sending to Agent: {prompt}")

        # Extract actor_id (user identifier) for memory
        actor_id = request_data.get('userId', request_data.get('user_id', 'anonymous'))

        # X-Ray: Create subsegment for Agent invocation with annotations for transaction search
        if XRAY_AVAILABLE:
            xray_recorder.begin_subsegment('AgentCore.invoke')
            try:
                xray_recorder.put_annotation('backend', backend)
                xray_recorder.put_annotation('sessionId', session_id)
                xray_recorder.put_annotation('agentRuntimeArn', runtime_arn)
                xray_recorder.put_annotation('actorId', actor_id)
                xray_recorder.put_annotation('conversationType', conversation_type)
            except Exception as e:
                logger.warning(f"Failed to add X-Ray annotations: {e}")

        try:
            # Call Agent Runtime with text + controls + session/actor info for memory
            agent_client = AgentCoreClient(runtime_arn, session_id=session_id)
            agent_response = agent_client.ask_agent(prompt, controls=controls, session_id=session_id, actor_id=actor_id)
        finally:
            if XRAY_AVAILABLE:
                try:
                    xray_recorder.end_subsegment()
                except Exception:
                    pass

        # Extract answer from Agent response
        answer = ""
        sources = []
        if isinstance(agent_response, dict):
            answer = agent_response.get('response', '') or agent_response.get('answer', '')
            sources = agent_response.get('sources', [])
        elif isinstance(agent_response, str):
            answer = agent_response

        if not answer:
            answer = "I couldn't generate an answer for that question."

        return create_success_response({
            "answer": answer,
            "response": answer,            # keep both keys for UI compatibility
            "sessionId": session_id,
            "backend": backend,
            "sources": sources
        })

    except Exception as e:
        logger.error(f"Error in handle_chat_request: {e}")
        logger.error(f"Exception type: {type(e).__name__}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return create_error_response(500, f"Failed to process chat request: {str(e)}")


# ----------------------------
# Lambda entrypoint
# ----------------------------
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for routing requests to Agent Runtime.

    For backend=coveoMCP (your UI/BFF case), this function normalizes input into:
        { sessionId, text (question|query), controls? }
    and calls the Agent runtime. The Agent then decides which MCP tools to call.
    """
    try:
        logger.info(f"AgentCore request: {json.dumps(event, default=str)[:2000]}")

        # Health / preflight
        if event.get('httpMethod') == 'OPTIONS':
            return create_success_response({"ok": True})
        if event.get('path') in ('/health', '/healthz'):
            return create_success_response({"status": "ok"})

        # Resolve runtime ARN
        try:
            runtime_arn = get_runtime_arn()
        except Exception as e:
            logger.error(f"Runtime ARN not configured: {e}")
            return create_error_response(503, "AgentCore Runtime not configured")

        # Parse API Gateway request
        http_method = event.get('httpMethod', 'POST')
        path = event.get('path', '')
        body = event.get('body', '{}')
        try:
            request_data = json.loads(body) if isinstance(body, str) else (body or {})
        except json.JSONDecodeError:
            return create_error_response(400, "Invalid JSON in request body")

        # Decide routing; for coveoMCP we unify to chat handler
        backend_mode = request_data.get('backendMode', request_data.get('backend', 'coveoMCP'))

        if backend_mode == 'coveoMCP' or path.endswith('/agentcore') or path.endswith('/chat'):
            return handle_chat_request(request_data, runtime_arn)

        # Fallback: also allow direct text calls (non-HTTP or unknown route)
        question = request_data.get('question', '') or request_data.get('query', '') or request_data.get('text', '')
        if question:
            return handle_chat_request(request_data, runtime_arn)

        return create_error_response(400, "Unsupported route or missing question")

    except Exception as e:
        logger.error(f"Unexpected error in lambda_handler: {e}")
        return create_error_response(500, "Internal server error")


# ----------------------------
# Responses
# ----------------------------
def create_success_response(data: Any) -> Dict[str, Any]:
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        },
        'body': json.dumps(data, default=str)
    }


def create_error_response(status_code: int, message: str) -> Dict[str, Any]:
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        },
        'body': json.dumps({'error': message, 'statusCode': status_code})
    }
