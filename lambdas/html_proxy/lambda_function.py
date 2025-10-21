"""
Coveo HTML API Proxy Lambda.

This Lambda function handles HTML content requests for quick view functionality.
Uses Coveo Search API v2 HTML endpoint to get formatted content.

Environment Variables:
    - COVEO_ORG_ID: Coveo organization identifier
    - COVEO_SEARCH_API_KEY: Coveo API key (from Secrets Manager)
    - COVEO_PLATFORM_URL: Coveo Platform API base URL
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
            'platform_url': platform_url
        }
    except KeyError as e:
        logger.error(f"Missing required environment variable: {e}")
        raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Coveo HTML API proxy.
    
    Expects POST request with JSON body containing uniqueId, query, and requestedOutputSize.
    
    Returns:
        HTML content from Coveo API
    """
    logger.info(f"HTML request: {json.dumps(event, default=str)}")
    
    try:
        # Parse request parameters (POST request with JSON body)
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        unique_id = body.get('uniqueId', '')
        query = body.get('q', '')  # server.js now sends 'q' not 'query'
        requested_output_size = int(body.get('requestedOutputSize', 0))
        enable_navigation = 'false'  # Always false as per your specification
        
        if not unique_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'uniqueId parameter is required'})
            }
        
        logger.info(f"HTML request for uniqueId: {unique_id}, query: '{query}', size: {requested_output_size}")
        
        # Get Coveo configuration
        config = get_coveo_config()
        
        # Call Coveo HTML API
        html_content = call_coveo_html_api(
            unique_id=unique_id,
            query=query,
            requested_output_size=requested_output_size,
            enable_navigation=enable_navigation,
            config=config
        )
        
        logger.info(f"HTML request completed successfully, content length: {len(html_content)}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'text/html',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': html_content
        }
    
    except Exception as e:
        logger.error(f"HTML request error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }


def call_coveo_html_api(unique_id: str, query: str, requested_output_size: int, 
                       enable_navigation: str, config: Dict[str, str]) -> str:
    """
    Call Coveo HTML API v2.
    
    Args:
        unique_id: Unique identifier for the document
        query: Search query for context
        requested_output_size: Size of the output content
        enable_navigation: Whether to enable navigation
        config: Coveo configuration
        
    Returns:
        HTML content as string
    """
    org_id = config['org_id']
    api_key = config['api_key']
    platform_url = config['platform_url']
    
    # Build URL with query parameters
    params = parse.urlencode({
        'enableNavigation': enable_navigation,
        'q': query,
        'uniqueId': unique_id,
        'requestedOutputSize': str(requested_output_size)
    })
    
    url = f"{platform_url}/rest/search/v2/html?organizationId={org_id}&{params}"
    
    logger.debug(f"Coveo HTML API URL: {url}")
    
    # Create HTTP request
    req = request.Request(
        url,
        headers={
            'Authorization': f'Bearer {api_key}',
            'User-Agent': 'AWS-Workshop-Lambda/1.0'
        },
        method='GET'
    )
    
    try:
        with request.urlopen(req, timeout=30) as response:
            if response.status != 200:
                error_body = response.read().decode('utf-8')
                logger.error(f"Coveo API returned status {response.status}: {error_body}")
                raise Exception(f"Coveo API returned status {response.status}")
            
            # Handle HTML response
            html_content = response.read().decode('utf-8')
            logger.debug(f"Coveo API response length: {len(html_content)}")
            return html_content
    
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
            'uniqueId': 'test-unique-id',
            'query': 'cryptocurrency',
            'requestedOutputSize': 1000,
            'enableNavigation': 'false'
        })
    }
    
    # Set environment variables for testing
    os.environ.setdefault('COVEO_ORG_ID', 'your-org-id-here')
    os.environ.setdefault('COVEO_SEARCH_API_KEY', 'xx00000000-0000-0000-0000-000000000000')
    os.environ.setdefault('LOG_LEVEL', 'DEBUG')
    
    response = lambda_handler(test_event, None)
    print(json.dumps(response, indent=2))