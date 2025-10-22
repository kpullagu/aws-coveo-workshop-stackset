"""
Coveo Passage Retrieval API Proxy Lambda.

This Lambda function handles passage retrieval requests with the full Coveo Passages API payload format.

Environment Variables (Required):
    - COVEO_ORG_ID: Coveo organization identifier
    - COVEO_SEARCH_API_KEY: Coveo API key

Environment Variables (Optional):
    - COVEO_PLATFORM_URL: Coveo Platform API base URL (default: https://platform.cloud.coveo.com)
    - COVEO_SEARCH_HUB: Search Hub identifier (default: aws-workshop)
    - LOG_LEVEL: Logging level (default: INFO)
"""

import json
import logging
import os
import sys
import boto3
from urllib import request, error
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def get_coveo_config():
    """Get Coveo configuration from environment variables."""
    try:
        # Get all config from environment variables
        org_id = os.environ['COVEO_ORG_ID']
        api_key = os.environ['COVEO_SEARCH_API_KEY']
        platform_url = os.environ.get('COVEO_PLATFORM_URL', 'https://platform.cloud.coveo.com')
        search_hub = os.environ.get('COVEO_SEARCH_HUB', 'aws-workshop')
        
        if not api_key:
            raise ValueError("COVEO_SEARCH_API_KEY environment variable is empty")
        
        return {
            'org_id': org_id,
            'api_key': api_key,
            'platform_url': platform_url,
            'search_hub': search_hub
        }
    except KeyError as e:
        logger.error(f"Missing required environment variable: {e}")
        logger.error("Required: COVEO_ORG_ID, COVEO_SEARCH_API_KEY")
        raise

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Coveo Passage Retrieval API proxy.
    
    Expects POST request with Coveo Passages API payload in the body.
    
    Returns:
        Coveo Passages API response
    """
    logger.info(f"Passages request: {json.dumps(event, default=str)}")
    
    try:
        # Parse request body
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        logger.info(f"Passages payload: {json.dumps(body, indent=2)}")
        
        # Get Coveo configuration
        config = get_coveo_config()
        logger.info(f"Retrieving passages from Coveo org: {config['org_id']}")
        
        # Call Coveo Passages API with the provided payload
        passages_result = call_coveo_passages_api(body, config)
        
        logger.info(f"Passages retrieval completed successfully")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps(passages_result)
        }
    
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in request body: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body', 'details': str(e)})
        }
    
    except Exception as e:
        logger.error(f"Passages retrieval error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }


def call_coveo_passages_api(payload: Dict[str, Any], config: Dict[str, str]) -> Dict[str, Any]:
    """
    Call Coveo Passages API with the provided payload.
    
    Args:
        payload: Complete Coveo Passages API payload
        config: Coveo configuration
        
    Returns:
        Raw Coveo API response
    """
    org_id = config['org_id']
    api_key = config['api_key']
    platform_url = config['platform_url']
    
    # Build Passages API URL - Use Search API v2 for passage retrieval
    url = f"{platform_url}/rest/search/v3/passages/retrieve"
    
    # Ensure organizationId is set if not provided
    if 'organizationId' not in payload:
        payload['organizationId'] = org_id
    
    logger.debug(f"Coveo Passages API URL: {url}")
    logger.debug(f"Coveo Passages request payload: {json.dumps(payload, indent=2)}")
    
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
    test_event = {
        'body': json.dumps({
            'query': 'How to clean teak outdoor furniture?',
            'k': 3
        })
    }
    
    os.environ.setdefault('COVEO_ORG_ID', 'test-org')
    os.environ.setdefault('COVEO_SEARCH_API_KEY', 'xx00000000-0000-0000-0000-000000000000')
    os.environ.setdefault('LOG_LEVEL', 'DEBUG')
    
    response = lambda_handler(test_event, None)
    print(json.dumps(response, indent=2))
