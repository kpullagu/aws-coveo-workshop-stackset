"""
Coveo Search API Proxy Lambda.

This Lambda function proxies requests to the Coveo Search API to perform full-text
search across indexed content. It returns ranked search results with facets, snippets,
and metadata.

Key Features:
    - Performs full-text search using Coveo's Search API
    - Returns ranked results with relevance scoring
    - Supports faceted navigation and filtering
    - Provides query suggestions and result snippets
    - Used by the frontend for direct Coveo integration mode

Environment Variables (Required):
    - COVEO_ORG_ID: Coveo organization identifier
    - COVEO_SEARCH_API_KEY: Coveo API key with search permissions

Environment Variables (Optional):
    - COVEO_PLATFORM_URL: Coveo Platform API base URL (default: https://platform.cloud.coveo.com)
    - COVEO_SEARCH_HUB: Search Hub identifier for analytics (default: aws-workshop)
    - LOG_LEVEL: Logging level (default: INFO)
"""

import json
import logging
import os
import sys
import boto3
from urllib import request, error
from typing import Dict, Any

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
        
        logger.info(f"Successfully loaded Coveo configuration (API key length: {len(api_key)})")
        
        return {
            'org_id': org_id,
            'api_key': api_key,
            'platform_url': platform_url,
            'search_hub': search_hub
        }
    except KeyError as e:
        logger.error(f"Missing required environment variable: {e}")
        logger.error("Required environment variables:")
        logger.error("  - COVEO_ORG_ID: Coveo organization identifier")
        logger.error("  - COVEO_SEARCH_API_KEY: Coveo API key")
        raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for unified Coveo search.
    
    All backends (coveo, bedrockAgent, coveoMCP) use direct Coveo API calls.
    
    Returns:
        Coveo Search API response
    """
    logger.info(f"Search request: {json.dumps(event, default=str)}")
    
    try:
        # Parse request body
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        logger.info(f"Search payload: {json.dumps(body, indent=2)}")
        
        # Get backend mode for logging
        backend_mode = body.get('backendMode', 'coveo')
        logger.info(f"Backend mode: {backend_mode} (all use direct Coveo API)")
        
        # Get Coveo configuration
        config = get_coveo_config()
        logger.info(f"Searching Coveo org: {config['org_id']}")
        
        # Call Coveo Search API with the provided payload
        # All backends use the same direct API call
        search_results = call_coveo_search_api(body, config)
        
        logger.info(f"Search completed successfully, total results: {search_results.get('totalCount', 0)}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps(search_results)
        }
    
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in request body: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body', 'details': str(e)})
        }
    
    except Exception as e:
        logger.error(f"Search error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }


def call_coveo_search_api(payload: Dict[str, Any], config: Dict[str, str]) -> Dict[str, Any]:
    """
    Call Coveo Search API with the provided payload.
    
    Args:
        payload: Complete Coveo Search API payload
        config: Coveo configuration
        
    Returns:
        Raw Coveo API response
    """
    org_id = config['org_id']
    api_key = config['api_key']
    platform_url = config['platform_url']
    
    # Build Search API URL
    url = f"{platform_url}/rest/search/v2?organizationId={org_id}"
    
    # Ensure searchHub is set if not provided
    if 'searchHub' not in payload:
        payload['searchHub'] = config['search_hub']
    
    logger.debug(f"Coveo Search API URL: {url}")
    logger.debug(f"Coveo Search request payload: {json.dumps(payload, indent=2)}")
    
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
    test_payload = {
        "q": "machine learning",
        "numberOfResults": 20,
        "firstResult": 0,
        "searchHub": "aws-workshop",
        "facets": []
    }
    
    test_event = {
        'body': json.dumps(test_payload)
    }
    
    os.environ.setdefault('COVEO_ORG_ID', 'test-org')
    os.environ.setdefault('COVEO_SEARCH_API_KEY', 'xx00000000-0000-0000-0000-000000000000')
    os.environ.setdefault('LOG_LEVEL', 'DEBUG')
    
    response = lambda_handler(test_event, None)
    print(json.dumps(response, indent=2))