"""
Bedrock Agent Chat Adapter Lambda with Coveo Passages Integration.

This Lambda function:
1. Receives full Coveo search payload from frontend
2. Calls Coveo Passages API to retrieve relevant passages
3. Invokes Bedrock Agent with retrieved passages for grounded answers
4. Maintains sessionId for multi-turn conversation memory

Environment Variables (Required):
    - STACK_PREFIX: Stack prefix for SSM parameters

Environment Variables (Optional):
    - AWS_REGION: AWS region for Bedrock and SSM (default: us-east-1)
    - LOG_LEVEL: Logging level (default: INFO)

Request Body (Full Coveo Payload):
    {
        "q": "What are investment basics?",
        "sessionId": "uuid-v4-session-id",
        "backendMode": "bedrockAgent",
        "pipeline": "...",
        "pipelineRuleParameters": {...},
        "searchHub": "...",
        "facets": [...],
        "fieldsToInclude": [...],
        // ... full Coveo search configuration
    }

Response:
    {
        "answer": "Grounded answer based on retrieved passages",
        "citations": [...],
        "sessionId": "preserved-session-id",
        "confidence": 0.85
    }
"""

import json
import logging
import os
import urllib.request
import urllib.parse
import hashlib
from typing import Dict, Any, Generator, List
import boto3
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def get_stable_memory_id(event: Dict[str, Any], body: Dict[str, Any]) -> str:
    """
    Derive a stable memoryId for cross-session memory.
    
    Priority:
    1. Explicit memoryId from request body
    2. Cognito sub from JWT claims (most stable)
    3. Cognito email from JWT claims
    4. Fallback to "anonymous"
    
    Returns hashed value to normalize length and avoid PII leakage.
    """
    # Try explicit memoryId from request body
    if body.get("memoryId"):
        return str(body["memoryId"])[:256]
    
    # Try to get Cognito identity from authorizer claims
    try:
        claims = (event.get("requestContext", {})
                       .get("authorizer", {})
                       .get("jwt", {})
                       .get("claims", {}))
        
        # Prefer 'sub' (stable user ID) over email
        stable_source = claims.get("sub") or claims.get("email")
        
        if stable_source:
            # Hash to normalize length and avoid PII in logs
            return hashlib.sha256(stable_source.encode("utf-8")).hexdigest()
    except Exception as e:
        logger.warning(f"Could not extract identity from claims: {e}")
    
    # Fallback to anonymous (not ideal for memory, but safe)
    return hashlib.sha256("anonymous".encode("utf-8")).hexdigest()

# Initialize Bedrock Agent Runtime client
bedrock_agent_runtime = boto3.client(
    'bedrock-agent-runtime',
    region_name=os.environ.get('AWS_DEFAULT_REGION', 'us-east-1')
)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Bedrock Agent chat with multi-turn memory.
    
    Args:
        event: API Gateway event with body containing question and sessionId
        context: Lambda context
        
    Returns:
        API Gateway response with SSE stream or JSON answer
    """
    logger.info(f"Bedrock Agent chat request: {json.dumps(event)}")
    
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        # Support multiple query field names for compatibility
        question = body.get('query', '') or body.get('question', '') or body.get('q', '')
        question = question.strip()
        session_id = body.get('sessionId') or body.get('session_id')
        backend_mode = body.get('backendMode', 'bedrockAgent')
        conversation_type = body.get('conversationType', 'multi-turn')  # Default to multi-turn for backward compatibility
        
        logger.info(f"Received request - Query: {question[:50]}..., SessionId: {session_id[:8] if session_id else 'None'}..., Type: {conversation_type}")
        
        if not question:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing required field: question'})
            }
        
        # Handle session ID based on conversation type
        if conversation_type == 'single-turn':
            # For single-turn conversations, always generate a new session ID
            import uuid
            session_id = str(uuid.uuid4())
            logger.info(f"Single-turn mode: Generated new session ID {session_id[:8]}...")
        elif not session_id:
            # For multi-turn conversations, generate session ID if not provided
            import uuid
            session_id = str(uuid.uuid4())
            logger.warning(f"Multi-turn mode: No sessionId provided, generated {session_id[:8]}...")
        else:
            logger.info(f"Multi-turn mode: Using provided session ID {session_id[:8]}...")
        
        # Get configuration from SSM Parameter Store
        stack_prefix = os.environ.get('STACK_PREFIX', 'workshop')
        
        try:
            ssm_client = boto3.client('ssm', region_name=os.environ.get('AWS_DEFAULT_REGION', 'us-east-1'))
            
            # Get Agent ID from SSM
            agent_id_param = ssm_client.get_parameter(
                Name=f'/{stack_prefix}/coveo/agent-id'
            )
            agent_id = agent_id_param['Parameter']['Value']
            
            # Get Agent Alias ID from SSM
            alias_id_param = ssm_client.get_parameter(
                Name=f'/{stack_prefix}/coveo/agent-alias-id'
            )
            alias_id = alias_id_param['Parameter']['Value']
            
        except Exception as e:
            logger.error(f"Failed to get Bedrock Agent configuration from SSM: {str(e)}")
            return {
                'statusCode': 503,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'error': 'Bedrock Agent not configured',
                    'details': f'Failed to retrieve agent configuration: {str(e)}'
                })
            }
        
        # Get stable memoryId for cross-session memory
        memory_id = get_stable_memory_id(event, body)
        logger.info(f"Using memoryId: {memory_id[:16]}... for cross-session memory")
        
        # Check if this is an end-of-session request
        end_session = bool(body.get('endSession', False))
        if end_session:
            logger.info(f"End session requested - will finalize and summarize session {session_id[:8]}...")
        
        logger.info(f"Invoking Bedrock Agent {agent_id} (alias: {alias_id}) with session: {session_id[:8]}...")
        
        # Let the agent decide whether to call retrieve_passages tool
        # Do NOT pre-fetch passages - this allows agent to handle memory questions correctly
        
        # Invoke agent with memory-enabled session
        try:
            # Build invoke parameters
            invoke_params = {
                'agentId': agent_id,
                'agentAliasId': alias_id,
                'sessionId': session_id,  # Within-session continuity
                'inputText': question,  # Pass question directly, let agent decide what to do
                'enableTrace': False
            }
            
            # Add memoryId for cross-session memory (if memory is enabled in console)
            invoke_params['memoryId'] = memory_id
            
            # Add endSession flag to finalize and summarize the session
            if end_session:
                invoke_params['endSession'] = True
            
            logger.info(f"Invoke params: agentId={agent_id}, sessionId={session_id[:8]}, memoryId={memory_id[:16]}, endSession={end_session}")
            
            response = bedrock_agent_runtime.invoke_agent(**invoke_params)
            
            # Process streaming response
            final_text, agent_citations = process_agent_stream(response['completion'])
            
            # Return enhanced response with memory information
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization'
                },
                'body': json.dumps({
                    'response': final_text,  # Primary field expected by ChatBot
                    'answer': final_text,    # Backup field for compatibility
                    'citations': agent_citations,  # Citations from agent (includes tool results)
                    'memoryId': memory_id,   # Return memoryId for client tracking
                    'sessionEnded': end_session,  # Indicate if session was ended
                    'confidence': 0.90,
                    'usedTooling': ['bedrock.agent'],
                    'sessionId': session_id
                })
            }
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            error_message = e.response['Error']['Message']
            logger.error(f"Bedrock Agent error ({error_code}): {error_message}")
            
            return {
                'statusCode': 502,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'error': 'Bedrock Agent invocation failed',
                    'details': f"{error_code}: {error_message}"
                })
            }
    
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in request body: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }


def process_agent_stream(completion_stream):
    """
    Process Bedrock Agent streaming response.
    
    The completion stream contains EventStream events with chunks of text
    and optional citations/references.
    
    Args:
        completion_stream: EventStream from InvokeAgent response
        
    Returns:
        Tuple of (final_text, citations_list)
    """
    final_text = []
    citations = []
    
    try:
        for event in completion_stream:
            # Debug: log event types
            logger.debug(f"Agent event: {event.keys()}")
            
            # Extract text chunks
            if 'chunk' in event:
                chunk = event['chunk']
                
                # Handle text attribution (chunk with text)
                if 'bytes' in chunk:
                    text_chunk = chunk['bytes'].decode('utf-8')
                    final_text.append(text_chunk)
                    logger.debug(f"Text chunk: {text_chunk[:100]}")
                
                # Handle attribution (citations/sources)
                if 'attribution' in chunk:
                    attribution = chunk['attribution']
                    if 'citations' in attribution:
                        for citation in attribution['citations']:
                            # Extract citation details
                            refs = citation.get('retrievedReferences', [])
                            for ref in refs:
                                content = ref.get('content', {})
                                location = ref.get('location', {})
                                
                                citations.append({
                                    'title': content.get('title', 'Unknown'),
                                    'uri': location.get('s3Location', {}).get('uri', ''),
                                    'text': content.get('text', '')[:200]  # Preview
                                })
            
            # Handle trace events (optional for debugging)
            if 'trace' in event:
                trace = event['trace']
                logger.debug(f"Trace event: {json.dumps(trace)}")
    
    except Exception as e:
        logger.error(f"Error processing agent stream: {str(e)}", exc_info=True)
    
    return ''.join(final_text), citations[:5]  # Limit to top 5 citations
