"""
Coveo Query Suggest API Proxy Lambda.

This Lambda function handles query suggestion requests using Coveo Search API v3.
Provides autocomplete suggestions as users type in the search bar.

Environment Variables:
    - COVEO_ORG_ID: Coveo organization identifier
    - COVEO_SEARCH_API_KEY: Coveo API key (from Secrets Manager)
    - COVEO_PLATFORM_URL: Coveo Platform API base URL
    - COVEO_SEARCH_HUB: Search Hub identifier
    - COVEO_PIPELINE: Pipeline identifier
    - LOG_LEVEL: Logging level
"""

import json
import logging
import os
import boto3
from urllib import request, error, parse
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def get_coveo_config():
    """Get Coveo configuration from environment variables and Secrets Manager."""
    try:
        # Get basic config from environment
        org_id = os.environ['COVEO_ORG_ID']
        platform_url = os.environ.get('COVEO_PLATFORM_URL', 'https://platform.cloud.coveo.com')
        search_hub = os.environ.get('COVEO_SEARCH_HUB', 'aws-workshop')
        pipeline = os.environ.get('COVEO_PIPELINE', 'aws-workshop-pipeline')
        
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
            'search_hub': search_hub,
            'pipeline': pipeline
        }
    except KeyError as e:
        logger.error(f"Missing required environment variable: {e}")
        raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Coveo Query Suggest API proxy.
    
    Expects GET or POST request with query parameters or JSON body.
    
    Returns:
        Query suggestions from Coveo API
    """
    logger.info(f"Query suggest request: {json.dumps(event, default=str)}")
    
    try:
        # Parse request body - server.js now sends the full payload
        if 'body' in event:
            if isinstance(event['body'], str):
                payload = json.loads(event['body'])
            else:
                payload = event['body']
        else:
            payload = event
        
        logger.info(f"Query suggest payload: {json.dumps(payload, indent=2)}")
        
        # Get Coveo configuration
        config = get_coveo_config()
        
        # Call Coveo Query Suggest API with the full payload from server.js
        suggestions = call_coveo_query_suggest_api_direct(payload, config)
        
        logger.info(f"Query suggest completed successfully, {len(suggestions.get('completions', []))} suggestions")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
            },
            'body': json.dumps(suggestions)
        }
    
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in request body: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body', 'details': str(e)})
        }
    
    except Exception as e:
        logger.error(f"Query suggest error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }


def call_coveo_query_suggest_api_direct(payload: Dict[str, Any], config: Dict[str, str]) -> Dict[str, Any]:
    """
    Call Coveo Query Suggest API v2 with the payload from server.js.
    
    Args:
        payload: Complete payload from server.js
        config: Coveo configuration
        
    Returns:
        Query suggestions response
    """
    org_id = config['org_id']
    api_key = config['api_key']
    platform_url = config['platform_url']
    
    # Build URL with query parameters
    url = f"{platform_url}/rest/search/v2/querySuggest?organizationId={org_id}"
    
    logger.debug(f"Coveo Query Suggest API URL: {url}")
    logger.debug(f"Coveo Query Suggest request payload: {json.dumps(payload, indent=2)}")
    
    # Create HTTP request
    req = request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {api_key}',
            'User-Agent': 'AWS-Workshop-Lambda/1.0'
        },
        method='POST'
    )
    
    try:
        with request.urlopen(req, timeout=30) as response:
            if response.status != 200:
                error_body = response.read().decode('utf-8')
                logger.error(f"Coveo API returned status {response.status}: {error_body}")
                raise Exception(f"Coveo API returned status {response.status}")
            
            # Handle JSON response
            body = response.read().decode('utf-8')
            data = json.loads(body)
            logger.debug(f"Coveo API response: {json.dumps(data, indent=2)}")
            return data
    
    except error.HTTPError as e:
        error_body = e.read().decode('utf-8') if e.fp else 'No error details'
        logger.error(f"HTTP error from Coveo: {e.code} {e.reason}, body: {error_body}")
        raise Exception(f"Coveo API error: {e.code} {e.reason}")
    
    except error.URLError as e:
        logger.error(f"URL error calling Coveo: {str(e)}")
        raise Exception(f"Failed to connect to Coveo API: {str(e)}")


def call_coveo_query_suggest_api(query: str, count: int, config: Dict[str, str]) -> Dict[str, Any]:
    """
    Call Coveo Query Suggest API v3.
    
    Args:
        query: Search query for suggestions
        count: Number of suggestions to return
        config: Coveo configuration
        
    Returns:
        Query suggestions response
    """
    org_id = config['org_id']
    api_key = config['api_key']
    platform_url = config['platform_url']
    search_hub = config['search_hub']
    pipeline = config['pipeline']
    
    # Build URL with query parameters
    url = f"{platform_url}/rest/search/v3/querySuggest?organizationId={org_id}"
    
    # Build request payload
    payload = {
        'q': query,
        'count': count,
        'enableWorldCompletion': True,
        'searchHub': search_hub,
        'pipeline': pipeline,
        'recommendation': 'Recommendation',
        'locale': 'en-US',
        'timezone': 'America/New_York',
        'format': 'json',
        'debug': False,
        'mlParameters': {
            'num': 3,
            'padding': 'trending'
        },
        'pipelineRuleParameters': {
            'genqa': {
                'responseFormat': {
                    'answerStyle': 'bullet'
                }
            }
        },
        'analytics': {
            'capture': True,
            'trackingId': 'string',
            'clientId': 'string',
            'documentLocation': 'string',
            'documentReferrer': 'string',
            'pageId': 'string',
            'userIp': 'string',
            'clientRequestId': 'string',
            'clientTimestamp': 'string',
            'userAgent': 'string',
            'actionCause': 'facetSelect',
            'originContext': 'CommunitySearch',
            'customData': {}
        }
    }
    
    logger.debug(f"Coveo Query Suggest API URL: {url}")
    logger.debug(f"Coveo Query Suggest request payload: {json.dumps(payload, indent=2)}")
    
    # Create HTTP request
    req = request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {api_key}',
            'User-Agent': 'AWS-Workshop-Lambda/1.0'
        },
        method='POST'
    )
    
    try:
        with request.urlopen(req, timeout=30) as response:
            if response.status != 200:
                error_body = response.read().decode('utf-8')
                logger.error(f"Coveo API returned status {response.status}: {error_body}")
                raise Exception(f"Coveo API returned status {response.status}")
            
            # Handle JSON response
            body = response.read().decode('utf-8')
            data = json.loads(body)
            logger.debug(f"Coveo API response: {json.dumps(data, indent=2)}")
            return data
    
    except error.HTTPError as e:
        error_body = e.read().decode('utf-8') if e.fp else 'No error details'
        logger.error(f"HTTP error from Coveo: {e.code} {e.reason}, body: {error_body}")
        raise Exception(f"Coveo API error: {e.code} {e.reason}")
    
    except error.URLError as e:
        logger.error(f"URL error calling Coveo: {str(e)}")
        raise Exception(f"Failed to connect to Coveo API: {str(e)}")


# For local testing
if __name__ == '__main__':
    # Mock event for local testing
    test_event = {
        'httpMethod': 'POST',
        'body': json.dumps({
            'q': 'crypto',
            'count': 5
        })
    }
    
    # Set environment variables for testing
    os.environ.setdefault('COVEO_ORG_ID', 'your-org-id-here')
    os.environ.setdefault('COVEO_SEARCH_API_KEY', 'xx00000000-0000-0000-0000-000000000000')
    os.environ.setdefault('COVEO_SEARCH_HUB', 'your-search-hub')
    os.environ.setdefault('COVEO_PIPELINE', 'aws-workshop-pipeline')
    os.environ.setdefault('LOG_LEVEL', 'DEBUG')
    
    response = lambda_handler(test_event, None)
    print(json.dumps(response, indent=2))