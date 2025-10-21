"""
Bedrock Agent Lambda Tool for Coveo Passage Retrieval (Function Details format).

This Lambda function is designed to be used as a Bedrock Agent action group tool.
It retrieves relevant passages from Coveo to ground the Agent's responses.

Event Format (Bedrock Agent Function Details):
    {
        "messageVersion": "1.0",
        "agent": {
            "name": "...",
            "id": "...",
            "alias": "...",
            "version": "..."
        },
        "inputText": "User's full question",
        "sessionId": "...",
        "actionGroup": "...",
        "function": "retrieve_passages",
        "parameters": [
            {"name": "query", "type": "string", "value": "How to care for teak?"},
            {"name": "k", "type": "number", "value": "5"}
        ]
    }

Response Format (Bedrock Agent Function Details):
    {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": "...",
            "function": "retrieve_passages",
            "functionResponse": {
                "responseBody": {
                    "TEXT": {
                        "body": "{\"passages\": [...]}"  # JSON string
                    }
                }
            }
        }
    }
"""

import json
import logging
import os
import sys
from urllib import request, error
from typing import Dict, Any, List

# Add config directory to path
sys.path.insert(0, '/opt/python')
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import boto3

def get_coveo_config():
    """Get Coveo configuration from environment variables and Secrets Manager."""
    try:
        # Get basic config from environment
        org_id = os.environ['COVEO_ORG_ID']
        platform_url = os.environ.get('COVEO_PLATFORM_URL', 'https://platform.cloud.coveo.com')
        search_hub = os.environ.get('COVEO_SEARCH_HUB', 'aws-workshop')
        
        # Get API key from SSM Parameter Store
        ssm_client = boto3.client('ssm')
        param_name = os.environ.get('COVEO_SEARCH_API_KEY_PARAM', '/workshop/coveo/search-api-key')
        
        try:
            response = ssm_client.get_parameter(Name=param_name, WithDecryption=False)
            api_key = response['Parameter']['Value']
        except Exception as e:
            logger.warning(f"Failed to get API key from SSM: {e}")
            # Fallback to environment variable
            api_key = os.environ.get('COVEO_SEARCH_API_KEY', '')
        
        return {
            'org_id': org_id,
            'api_key': api_key,
            'platform_url': platform_url,
            'search_hub': search_hub
        }
    except KeyError as e:
        logger.error(f"Missing required environment variable: {e}")
        raise

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Bedrock Agent tool (Function Details format).
    
    Args:
        event: Bedrock Agent event with function parameters
        context: Lambda context
        
    Returns:
        Bedrock Agent function response
    """
    logger.info(f"Bedrock Agent tool invoked: {json.dumps(event)}")
    
    try:
        # Extract parameters from Bedrock Agent event
        message_version = event.get('messageVersion', '1.0')
        action_group = event.get('actionGroup', '')
        function_name = event.get('function', 'retrieve_passages')
        input_text = event.get('inputText', '')
        parameters = event.get('parameters', [])
        
        # Parse parameters
        param_dict = {}
        for param in parameters:
            param_name = param.get('name')
            param_value = param.get('value')
            param_dict[param_name] = param_value
        
        # Get query and k from parameters
        query = param_dict.get('query', input_text).strip()
        k = int(param_dict.get('k', 5))
        
        if not query:
            error_response = {
                'messageVersion': message_version,
                'response': {
                    'actionGroup': action_group,
                    'function': function_name,
                    'functionResponse': {
                        'responseBody': {
                            'TEXT': {
                                'body': json.dumps({
                                    'error': 'Missing required parameter: query'
                                })
                            }
                        }
                    }
                }
            }
            return error_response
        
        # Get Coveo configuration
        config = get_coveo_config()
        logger.info(f"Retrieving {k} passages for query: '{query}'")
        
        # Call Coveo Passage Retrieval API
        passages = retrieve_passages(query, k, config)
        
        # Format response for Bedrock Agent
        response_body = {
            'passages': passages,
            'totalCount': len(passages),
            'query': query
        }
        
        bedrock_response = {
            'messageVersion': message_version,
            'response': {
                'actionGroup': action_group,
                'function': function_name,
                'functionResponse': {
                    'responseBody': {
                        'TEXT': {
                            'body': json.dumps(response_body)
                        }
                    }
                }
            }
        }
        
        logger.info(f"Returning {len(passages)} passages to Bedrock Agent")
        return bedrock_response
    
    except Exception as e:
        logger.error(f"Error in Bedrock Agent tool: {str(e)}", exc_info=True)
        
        # Return error in Bedrock Agent format
        error_response = {
            'messageVersion': event.get('messageVersion', '1.0'),
            'response': {
                'actionGroup': event.get('actionGroup', ''),
                'function': event.get('function', 'retrieve_passages'),
                'functionResponse': {
                    'responseBody': {
                        'TEXT': {
                            'body': json.dumps({
                                'error': 'Failed to retrieve passages',
                                'details': str(e)
                            })
                        }
                    }
                }
            }
        }
        return error_response


def retrieve_passages(query: str, k: int, config: Dict[str, str]) -> List[Dict[str, Any]]:
    """
    Retrieve relevant passages from Coveo Passage Retrieval API.
    
    Args:
        query: User's question
        k: Number of passages to return
        config: Coveo configuration
        
    Returns:
        List of passage dictionaries
    """
    org_id = config['org_id']
    api_key = config['api_key']
    platform_url = config['platform_url']
    search_hub = config['search_hub']
    
    # Build Passage Retrieval API URL - Use correct v3 endpoint
    url = f"{platform_url}/rest/search/v3/passages/retrieve"
    
    # Prepare request payload - Use correct format matching passages_proxy
    payload = {
        'query': query,
        'numberOfPassages': k,
        'organizationId': org_id,
        'pipeline': 'default',
        'searchHub': search_hub,
        'localization': {
            'locale': 'en-US',
            'fallbackLocale': 'en'
        },
        'additionalFields': ["title", "clickableuri", "project", "uniqueid", "summary"],
        'facets': [],
        'queryCorrection': {
            'enabled': True,
            'options': {
                'automaticallyCorrect': 'whenNoResults'
            }
        },
        'analytics': {
            'clientId': 'bedrock-agent-tool',
            'clientTimestamp': '2025-01-01T00:00:00.000Z',
            'originContext': 'BedrockAgentTool',
            'actionCause': 'passageRetrieval',
            'capture': False,
            'source': ['BedrockAgentTool@1.0.0']
        }
    }
    
    logger.debug(f"Calling Coveo Passage Retrieval API: {url}")
    logger.debug(f"Request payload: {json.dumps(payload)}")
    
    # Create HTTP request
    req = request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {api_key}'
        },
        method='POST'
    )
    
    try:
        with request.urlopen(req, timeout=30) as response:
            if response.status != 200:
                raise Exception(f"Coveo API returned status {response.status}")
            
            body = response.read().decode('utf-8')
            data = json.loads(body)
            
            logger.info(f"📄 Full Coveo API response: {json.dumps(data, indent=2)}")
            
            # Normalize response for Bedrock Agent - Handle v3 API response format
            # v3 API returns 'items' instead of 'passages'
            raw_passages = data.get('items', data.get('passages', []))
            logger.info(f"📊 Found {len(raw_passages)} raw passages in response")
            
            passages = []
            for i, passage in enumerate(raw_passages):
                logger.info(f"📄 Processing passage {i+1}: {list(passage.keys())}")
                document = passage.get('document', {})
                passages.append({
                    'text': passage.get('text', passage.get('content', passage.get('body', ''))),
                    'uri': document.get('clickableuri', passage.get('clickUri', passage.get('uri', ''))),
                    'title': document.get('title', passage.get('title', 'Untitled')),
                    'score': passage.get('relevanceScore', passage.get('score', 0.0)),
                    'project': document.get('project', passage.get('project', 'Unknown')),
                    'uniqueid': document.get('uniqueid', passage.get('uniqueid', ''))
                })
            
            logger.info(f"✅ Processed {len(passages)} passages for Bedrock Agent")
            
            return passages
    
    except error.HTTPError as e:
        error_body = e.read().decode('utf-8') if e.fp else 'No error details'
        logger.error(f"HTTP error from Coveo: {e.code} {e.reason}, body: {error_body}")
        raise Exception(f"Coveo API error: {e.code} {e.reason}")
    
    except error.URLError as e:
        logger.error(f"URL error calling Coveo: {str(e)}")
        raise Exception(f"Failed to connect to Coveo API: {str(e)}")


# For local testing
if __name__ == '__main__':
    # Mock Bedrock Agent event
    test_event = {
        'messageVersion': '1.0',
        'agent': {
            'name': 'CoveoWorkshopAgent',
            'id': 'TESTAGENT',
            'alias': 'TSTALIASID',
            'version': 'DRAFT'
        },
        'inputText': 'How do I clean my teak furniture?',
        'sessionId': 'test-session-123',
        'actionGroup': 'CoveoPassageRetrieval',
        'function': 'retrieve_passages',
        'parameters': [
            {'name': 'query', 'type': 'string', 'value': 'How to clean teak furniture'},
            {'name': 'k', 'type': 'number', 'value': '5'}
        ]
    }
    
    os.environ.setdefault('COVEO_ORG_ID', 'test-org')
    os.environ.setdefault('COVEO_SEARCH_API_KEY', 'xx00000000-0000-0000-0000-000000000000')
    os.environ.setdefault('LOG_LEVEL', 'DEBUG')
    
    response = lambda_handler(test_event, None)
    print(json.dumps(response, indent=2))
