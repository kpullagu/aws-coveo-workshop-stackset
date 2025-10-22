"""
Coveo Answering API Proxy Lambda.

This Lambda function handles answer generation requests with the full Coveo Answer API payload format.
Supports both 'coveo' and 'bedrockAgent' modes.

Environment Variables (Required):
    - COVEO_ORG_ID: Coveo organization identifier
    - COVEO_SEARCH_API_KEY: Coveo API key
    - COVEO_ANSWER_CONFIG_ID: Answer configuration ID

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
        answer_config_id = os.environ.get('COVEO_ANSWER_CONFIG_ID', '')
        
        if not api_key:
            raise ValueError("COVEO_SEARCH_API_KEY environment variable is empty")
        
        return {
            'org_id': org_id,
            'api_key': api_key,
            'answer_config_id': answer_config_id,
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
    Lambda handler for Coveo Answer API proxy.
    
    Expects POST request with Coveo Answer API payload in the body.
    Supports both 'coveo' and 'bedrockAgent' modes.
    
    Returns:
        Coveo Answer API response
    """
    logger.info(f"Answer request: {json.dumps(event, default=str)}")
    
    try:
        # Parse request body
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        logger.info(f"Answer payload: {json.dumps(body, indent=2)}")
        
        # Check if this is a BedrockAgent request
        backend_mode = body.get('backendMode', 'coveo')
        session_id = body.get('sessionId')
        
        # Get Coveo configuration
        config = get_coveo_config()
        logger.info(f"Generating answer from Coveo org: {config['org_id']}, mode: {backend_mode}")
        
        if backend_mode == 'bedrockAgent' and session_id:
            # For BedrockAgent mode, we might want to call a different endpoint or add session handling
            # For now, we'll use the same Coveo Answer API but could extend this later
            logger.info(f"BedrockAgent mode with session: {session_id}")
        
        # Call Coveo Answer API with the provided payload
        answer_result = call_coveo_answer_api(body, config)
        
        # Add session info for BedrockAgent mode
        if backend_mode == 'bedrockAgent' and session_id:
            answer_result['sessionId'] = session_id
            answer_result['backendMode'] = backend_mode
        
        # Log the final response structure
        logger.info(f"Final Lambda response structure: {json.dumps({
            'hasAnswer': bool(answer_result.get('answer') or answer_result.get('answerText') or answer_result.get('response')),
            'answerLength': len(answer_result.get('answer', '') or answer_result.get('answerText', '') or answer_result.get('response', '')),
            'hasCitations': bool(answer_result.get('citations') and len(answer_result.get('citations', [])) > 0),
            'citationsCount': len(answer_result.get('citations', [])),
            'responseKeys': list(answer_result.keys())
        })}")
        
        logger.info(f"Full Lambda response: {json.dumps(answer_result, default=str)}")
        logger.info("Answer generation completed successfully")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps(answer_result)
        }
    
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in request body: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body', 'details': str(e)})
        }
    
    except Exception as e:
        logger.error(f"Answer generation error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }


def call_coveo_answer_api(payload: Dict[str, Any], config: Dict[str, str]) -> Dict[str, Any]:
    """
    Call Coveo Answer API with the provided payload and handle SSE streaming.
    
    Args:
        payload: Complete Coveo Answer API payload
        config: Coveo configuration
        
    Returns:
        Processed answer response with streaming data collected
    """
    org_id = config['org_id']
    api_key = config['api_key']
    platform_url = config['platform_url']
    answer_config_id = config.get('answer_config_id', '')
    
    if not answer_config_id:
        logger.error("No answer_config_id provided, cannot use Answer API v1")
        raise Exception("Answer configuration ID is required for Answer API")
    
    # Use Coveo Answer API v1 with SSE streaming
    url = f"{platform_url}/rest/organizations/{org_id}/answer/v1/configs/{answer_config_id}/generate"
    
    logger.debug(f"Coveo Answer API URL: {url}")
    logger.debug(f"Coveo Answer request payload: {json.dumps(payload, indent=2)}")
    
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
        with request.urlopen(req, timeout=60) as response:
            if response.status != 200:
                error_body = response.read().decode('utf-8')
                logger.error(f"Coveo API returned status {response.status}: {error_body}")
                raise Exception(f"Coveo API returned status {response.status}")
            
            # Check if this is an SSE stream
            content_type = response.headers.get('Content-Type', '')
            if 'text/event-stream' in content_type:
                logger.info("Processing SSE stream from Answer API")
                return process_sse_stream(response)
            else:
                # Handle regular JSON response
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


def process_sse_stream(response) -> Dict[str, Any]:
    """
    Process Server-Sent Events stream from Coveo Answer API.
    
    Args:
        response: HTTP response object with SSE stream
        
    Returns:
        Processed answer data with enhanced structure
    """
    answer_data = {
        'answer': '',
        'answerText': '',
        'response': '',
        'citations': [],
        'answerGenerated': False,
        'responseId': None,
        'finishReason': None
    }
    
    events_processed = 0
    
    try:
        # Read the entire stream
        stream_data = response.read().decode('utf-8')
        logger.info(f"SSE stream length: {len(stream_data)} characters")
        
        # Parse SSE events
        events = parse_sse_events(stream_data)
        logger.info(f"Parsed {len(events)} SSE events")
        
        for event in events:
            events_processed += 1
            logger.info(f"Processing SSE event {events_processed}: {json.dumps(event, default=str)}")
            
            if event.get('event') == 'message' and event.get('data'):
                try:
                    message_data = json.loads(event['data'])
                    payload_type = message_data.get('payloadType', '')
                    payload = message_data.get('payload', '')
                    
                    logger.info(f"Event payload type: {payload_type}")
                    
                    if payload_type == 'genqa.messageType':
                        # Parse the nested payload for text delta
                        if payload:
                            try:
                                nested_data = json.loads(payload)
                                text_delta = nested_data.get('textDelta', '')
                                if text_delta:
                                    answer_data['answer'] += text_delta
                                    answer_data['answerText'] += text_delta
                                    answer_data['response'] += text_delta
                                    logger.info(f"Added text delta: '{text_delta}' (total length: {len(answer_data['answer'])})")
                            except json.JSONDecodeError:
                                logger.warning(f"Failed to parse nested payload: {payload}")
                    
                    elif payload_type == 'genqa.textDeltaMessageType':
                        # Fallback for direct text delta (if format changes)
                        if payload:
                            answer_data['answer'] += payload
                            answer_data['answerText'] += payload
                            answer_data['response'] += payload
                            logger.info(f"Added direct text delta: '{payload}' (total length: {len(answer_data['answer'])})")
                    
                    elif payload_type == 'genqa.citationsType':
                        # Parse citations with enhanced structure
                        if payload:
                            try:
                                citations_data = json.loads(payload)
                                citations_list = citations_data.get('citations', [])
                                if citations_list:
                                    processed_citations = []
                                    for citation in citations_list:
                                        processed_citation = {
                                            'title': citation.get('title', ''),
                                            'uri': citation.get('clickUri') or citation.get('uri', ''),
                                            'clickUri': citation.get('clickUri') or citation.get('uri', ''),
                                            'clickableuri': citation.get('clickUri') or citation.get('uri', ''),
                                            'project': citation.get('fields', {}).get('project', 'unknown'),
                                            'text': citation.get('text', '')
                                        }
                                        processed_citations.append(processed_citation)
                                    answer_data['citations'] = processed_citations
                                    logger.info(f"Processed {len(processed_citations)} citations")
                            except json.JSONDecodeError:
                                logger.warning(f"Failed to parse citations payload: {payload}")
                    
                    elif payload_type == 'genqa.citationsMessageType':
                        # Legacy citations format
                        if payload:
                            try:
                                citations_data = json.loads(payload)
                                if isinstance(citations_data, list):
                                    answer_data['citations'] = citations_data
                                    logger.info(f"Processed {len(citations_data)} legacy citations")
                            except json.JSONDecodeError:
                                logger.warning(f"Failed to parse legacy citations payload: {payload}")
                    
                    elif payload_type == 'genqa.endOfStreamType':
                        # Handle end of stream
                        if payload:
                            try:
                                end_data = json.loads(payload)
                                answer_data['answerGenerated'] = end_data.get('answerGenerated', True)
                                logger.info(f"End of stream reached, answer generated: {answer_data['answerGenerated']}")
                            except json.JSONDecodeError:
                                answer_data['answerGenerated'] = True
                                logger.info("End of stream reached (fallback)")
                    
                    elif payload_type == 'genqa.headerMessageType':
                        # Parse header information
                        if payload:
                            try:
                                header_data = json.loads(payload)
                                logger.info(f"Header data: {json.dumps(header_data, default=str)}")
                            except json.JSONDecodeError:
                                logger.warning(f"Failed to parse header payload: {payload}")
                    
                    # Check for finish reason
                    finish_reason = message_data.get('finishReason')
                    if finish_reason:
                        answer_data['finishReason'] = finish_reason
                        logger.info(f"Finish reason: {finish_reason}")
                        
                except json.JSONDecodeError as e:
                    logger.warning(f"Failed to parse SSE message data: {e}")
                    continue
            else:
                logger.info(f"Skipping non-message event: {event.get('event', 'unknown')}")
        
        logger.info(f"Processed {events_processed} total events")
        logger.info(f"Processed answer text length: {len(answer_data['answer'])}")
        logger.info(f"Citations count: {len(answer_data['citations'])}")
        
        # Log final response structure
        logger.info(f"Final response structure: {json.dumps({
            'hasAnswer': bool(answer_data['answer']),
            'answerLength': len(answer_data['answer']),
            'hasCitations': bool(answer_data['citations']),
            'citationsCount': len(answer_data['citations']),
            'answerGenerated': answer_data['answerGenerated']
        })}")
        
        return answer_data
        
    except Exception as e:
        logger.error(f"Error processing SSE stream: {str(e)}", exc_info=True)
        raise Exception(f"Failed to process answer stream: {str(e)}")


def parse_sse_events(stream_data: str) -> list:
    """
    Parse Server-Sent Events from stream data with enhanced logging.
    
    Args:
        stream_data: Raw SSE stream data
        
    Returns:
        List of parsed events
    """
    events = []
    current_event = {}
    line_count = 0
    
    logger.info(f"Parsing SSE stream with {len(stream_data)} characters")
    
    for line in stream_data.split('\n'):
        line_count += 1
        line = line.strip()
        
        if not line:
            # Empty line indicates end of event
            if current_event:
                events.append(current_event)
                logger.debug(f"Completed event {len(events)}: {current_event.get('event', 'message')}")
                current_event = {}
            continue
        
        if line.startswith('event:'):
            current_event['event'] = line[6:].strip()
        elif line.startswith('data:'):
            data = line[5:].strip()
            if 'data' in current_event:
                current_event['data'] += '\n' + data
            else:
                current_event['data'] = data
        elif line.startswith('id:'):
            current_event['id'] = line[3:].strip()
        elif line.startswith('retry:'):
            current_event['retry'] = line[6:].strip()
        else:
            logger.debug(f"Unrecognized SSE line format: {line}")
    
    # Add final event if exists
    if current_event:
        events.append(current_event)
        logger.debug(f"Added final event {len(events)}: {current_event.get('event', 'message')}")
    
    logger.info(f"Parsed {len(events)} events from {line_count} lines")
    return events





# For local testing
if __name__ == '__main__':
    # Mock event for local testing
    test_event = {
        'body': json.dumps({
            'q': 'How does ACH work?',
            'pipelineRuleParameters': {
                'mlGenerativeQuestionAnswering': {
                    'responseFormat': {
                        'contentFormat': ['text/markdown', 'text/plain']
                    },
                    'citationsFieldToInclude': ['filetype', 'project', 'documenttype']
                }
            },
            'searchHub': 'aws-workshop'
        })
    }
    
    # Set environment variables for testing
    os.environ.setdefault('COVEO_ORG_ID', 'test-org')
    os.environ.setdefault('COVEO_SEARCH_API_KEY', 'xx00000000-0000-0000-0000-000000000000')
    os.environ.setdefault('COVEO_ANSWER_CONFIG_ID', '00000000-0000-0000-0000-000000000000')
    os.environ.setdefault('LOG_LEVEL', 'DEBUG')
    
    response = lambda_handler(test_event, None)
    print(json.dumps(response, indent=2))
