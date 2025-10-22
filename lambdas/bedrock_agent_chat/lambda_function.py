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
from typing import Dict, Any, Generator, List
import boto3
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize Bedrock Agent Runtime client
bedrock_agent_runtime = boto3.client(
    'bedrock-agent-runtime',
    region_name=os.environ.get('AWS_DEFAULT_REGION', 'us-east-1')
)

def get_coveo_passages(query: str, coveo_payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Retrieve passages from Coveo Passages API using the optimized payload structure.
    
    Args:
        query: The search query
        coveo_payload: Optimized Coveo passages payload from frontend
        
    Returns:
        List of passage objects with content and metadata
    """
    try:
        # Get Coveo configuration from SSM Parameter Store
        ssm_client = boto3.client('ssm', region_name=os.environ.get('AWS_DEFAULT_REGION', 'us-east-1'))
        stack_prefix = os.environ.get('STACK_PREFIX', 'workshop')
        
        # Get Coveo API key from SSM Parameter Store
        param_name = f'/{stack_prefix}/coveo/search-api-key'
        try:
            response = ssm_client.get_parameter(Name=param_name, WithDecryption=False)
            coveo_api_key = response['Parameter']['Value']
        except Exception as e:
            logger.error(f"Failed to get API key from SSM: {e}")
            raise Exception(f"Could not retrieve Coveo API key from SSM Parameter Store: {param_name}")
        
        # Use organization ID from payload (more efficient)
        coveo_org_id = coveo_payload.get('organizationId')
        if not coveo_org_id:
            # Fallback to SSM if not in payload
            coveo_org_id = ssm_client.get_parameter(Name=f'/{stack_prefix}/coveo/org-id')['Parameter']['Value']
        
        # Prepare optimized Coveo Passages API payload matching server.js format
        passages_payload = {
            'query': query,  # Use 'query' not 'q' to match server.js format
            'organizationId': coveo_org_id,  # Required for v3 API
            'numberOfPassages': coveo_payload.get('numberOfPassages', 5),
            'pipeline': coveo_payload.get('pipeline', 'default'),
            'searchHub': coveo_payload.get('searchHub', 'default'),
            'localization': coveo_payload.get('localization', {'locale': 'en-US', 'fallbackLocale': 'en'}),
            'additionalFields': coveo_payload.get('additionalFields', ["title", "clickableuri", "project", "uniqueid", "summary"]),
            'facets': coveo_payload.get('facets', []),
            'queryCorrection': coveo_payload.get('queryCorrection', {'enabled': True, 'options': {'automaticallyCorrect': 'whenNoResults'}}),
            'analytics': coveo_payload.get('analytics', {})
        }
        
        # Coveo Passages API URL - Use the correct v3 endpoint
        passages_url = f'https://platform.cloud.coveo.com/rest/search/v3/passages/retrieve'
        
        # Prepare request
        headers = {
            'Authorization': f'Bearer {coveo_api_key}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }
        
        data = json.dumps(passages_payload).encode('utf-8')
        req = urllib.request.Request(passages_url, data=data, headers=headers, method='POST')
        
        logger.info(f"Calling Coveo Passages API for query: {query[:50]}...")
        logger.info(f"🔗 API URL: {passages_url}")
        logger.info(f"📦 Request payload: {json.dumps(passages_payload, indent=2)}")
        logger.info(f"🔑 Using API key: {coveo_api_key[:10]}...{coveo_api_key[-4:]}")
        logger.info(f"🏢 Organization ID: {coveo_org_id}")
        
        # Make request to Coveo
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                if response.status == 200:
                    result = json.loads(response.read().decode('utf-8'))
                    logger.info(f"📄 Full API response: {json.dumps(result, indent=2)}")
                    
                    # v3 API returns 'items' instead of 'passages'
                    passages = result.get('items', result.get('passages', []))
                    logger.info(f"✅ Retrieved {len(passages)} passages from Coveo")
                    logger.info(f"📄 Response structure: {list(result.keys())}")
                    
                    if len(passages) == 0:
                        logger.warning("⚠️ No passages found in response - checking response content")
                        logger.warning(f"⚠️ Response keys: {list(result.keys())}")
                        logger.warning(f"⚠️ Items count: {len(result.get('items', []))}")
                        if 'items' in result:
                            logger.warning(f"⚠️ First item structure: {list(result['items'][0].keys()) if result['items'] else 'No items'}")
                    
                    return passages
                else:
                    error_body = response.read().decode('utf-8')
                    logger.error(f"❌ Coveo Passages API error: {response.status}")
                    logger.error(f"❌ Error response body: {error_body}")
                    return []
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8') if e.fp else 'No error details'
            logger.error(f"❌ HTTP error from Coveo: {e.code} {e.reason}")
            logger.error(f"❌ Error response body: {error_body}")
            return []
        except urllib.error.URLError as e:
            logger.error(f"❌ URL error calling Coveo: {str(e)}")
            return []
        except Exception as e:
            logger.error(f"❌ Unexpected error calling Coveo Passages API: {str(e)}")
            return []
            
    except Exception as e:
        logger.error(f"❌ Error in get_coveo_passages function: {str(e)}")
        return []


def format_passages_for_agent(passages: List[Dict[str, Any]]) -> str:
    """
    Format retrieved passages for Bedrock Agent consumption.
    
    Args:
        passages: List of passage objects from Coveo
        
    Returns:
        Formatted string with passages and metadata
    """
    if not passages:
        return "No relevant passages found."
    
    formatted_passages = []
    for i, passage in enumerate(passages[:5], 1):  # Limit to top 5
        # Handle the actual API response structure
        document = passage.get('document', {})
        content = passage.get('text', passage.get('content', ''))
        title = document.get('title', passage.get('title', 'Unknown'))
        uri = document.get('clickableuri', passage.get('clickUri', passage.get('uri', '')))
        project = document.get('project', passage.get('project', 'Unknown'))
        
        formatted_passage = f"""
Passage {i}:
Title: {title}
Source: {project}
Content: {content}
URL: {uri}
---"""
        formatted_passages.append(formatted_passage)
    
    return "\n".join(formatted_passages)


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
        
        logger.info(f"Invoking Bedrock Agent {agent_id} (alias: {alias_id}) with session: {session_id[:8]}...")
        
        # Step 1: Retrieve passages from Coveo
        logger.info("Retrieving relevant passages from Coveo...")
        passages = get_coveo_passages(question, body)
        formatted_passages = format_passages_for_agent(passages)
        
        # Step 2: Prepare enhanced input for Bedrock Agent with passages
        enhanced_input = f"""
User Question: {question}

Relevant Information:
{formatted_passages}

Please provide a comprehensive answer based on the above information. Include citations where appropriate.
"""
        
        logger.info(f"Enhanced input prepared with {len(passages)} passages")
        
        # Step 3: Invoke agent with memory-enabled session and passages
        try:
            response = bedrock_agent_runtime.invoke_agent(
                agentId=agent_id,
                agentAliasId=alias_id,
                sessionId=session_id,  # <<-- Enables multi-turn memory
                inputText=enhanced_input,  # <<-- Enhanced with passages
                enableTrace=False  # Set to True for debugging
            )
            
            # Process streaming response
            final_text, agent_citations = process_agent_stream(response['completion'])
            
            # Combine agent citations with passage citations
            passage_citations = []
            for passage in passages[:3]:  # Top 3 passages as citations
                # Handle the actual API response structure
                document = passage.get('document', {})
                passage_citations.append({
                    'title': document.get('title', passage.get('title', 'Unknown')),
                    'uri': document.get('clickableuri', passage.get('clickUri', passage.get('uri', ''))),
                    'text': passage.get('text', passage.get('content', ''))[:200] + '...',  # Preview
                    'project': document.get('project', passage.get('project', 'Unknown')),
                    'uniqueid': document.get('uniqueid', passage.get('uniqueid', '')),
                    'source': 'coveo_passages'
                })
            
            # Combine citations (agent citations + passage citations)
            all_citations = agent_citations + passage_citations
            
            # Return enhanced response
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
                    'citations': all_citations,
                    'confidence': 0.90,  # Higher confidence with grounded passages
                    'usedTooling': ['coveo.passages', 'bedrock.agent'],
                    'sessionId': session_id,
                    'passagesUsed': len(passages)
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
