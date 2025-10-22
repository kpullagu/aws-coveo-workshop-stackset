import os
from typing import Any, Dict, Optional, List
import httpx
import json
import boto3
import logging
from dotenv import load_dotenv
from dataclasses import dataclass, field

load_dotenv()

# Configure logging
logger = logging.getLogger(__name__)

# Coveo API constants - use platform.cloud.coveo.com with org subdomain
COVEO_SEARCH_API_ENDPOINT = "https://{org_id}.org.coveo.com/rest/search/v3?organizationId={org_id}"
COVEO_PASSAGES_API_ENDPOINT = "https://{org_id}.org.coveo.com/rest/search/v3/passages/retrieve?organizationId={org_id}"
COVEO_ANSWER_API_ENDPOINT = "https://{org_id}.org.coveo.com/rest/organizations/{org_id}/answer/v1/configs/{config_id}/generate"

# Load Coveo configuration from SSM Parameter Store
# AgentCore Runtime doesn't support environment variables in ContainerConfiguration
# So we read from SSM at runtime instead
import boto3

ssm = boto3.client('ssm')
STACK_PREFIX = "workshop"  # Default stack prefix

def get_ssm_parameter(name):
    """Get parameter from SSM Parameter Store."""
    try:
        response = ssm.get_parameter(Name=name, WithDecryption=True)
        return response['Parameter']['Value']
    except Exception as e:
        print(f"ERROR: Failed to get SSM parameter {name}: {e}")
        raise

# Read Coveo credentials from SSM
API_KEY = get_ssm_parameter(f'/{STACK_PREFIX}/coveo/search-api-key')
print(f"DEBUG: API_KEY={'***' + API_KEY[-4:] if API_KEY else 'None'}")

ORG_ID = get_ssm_parameter(f'/{STACK_PREFIX}/coveo/org-id')
print(f"DEBUG: ORG_ID={ORG_ID}")

ANSWER_CONFIG_ID = get_ssm_parameter(f'/{STACK_PREFIX}/coveo/answer-config-id')
print(f"DEBUG: ANSWER_CONFIG_ID={ANSWER_CONFIG_ID}")
USER_AGENT = "coveo-mcp-server/1.0"

@dataclass
class SearchContext:
    """Search context for Coveo queries."""
    q: str
    bearer_token: str = field(default_factory=lambda: API_KEY)
    organization_id: str = field(default_factory=lambda: ORG_ID)
    filter: Optional[str] = None
    locale: str = "en-US"
    timezone: str = "America/New_York"
    context: Optional[Dict[str, Any]] = None
    additionalFields: Optional[List[str]] = None

def format_search_response(response: Dict[str, Any], fields_to_include: List[str]) -> Dict[str, Any]:
    """
    Format the Coveo search response to include only specified fields.
    """
    if not response or "results" not in response:
        return {"results": []}
    
    formatted_results = []
    for result in response["results"]:
        formatted_result = {field: result.get(field) for field in fields_to_include if field in result}
        formatted_results.append(formatted_result)
    
    return {"results": formatted_results}

def format_passage_retrieval_response(response: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Format the Coveo passage retrieval response to extract relevant passages.
    """
    if not response:
        return []
    
    formatted_passages = []
    for item in response:
        passage = {
            "text": item.get("text", ""),
            "document": item.get("document", {})
        }
        formatted_passages.append(passage)
    
    return formatted_passages

async def make_coveo_request(payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Make a request to the Coveo API with proper error handling."""
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT
    }
    params = {}
    params["organizationId"] = ORG_ID
    endpoint = COVEO_SEARCH_API_ENDPOINT.format(org_id=ORG_ID)
    
    # Debug logging
    print(f"DEBUG search_coveo: ORG_ID={ORG_ID}")
    print(f"DEBUG search_coveo: endpoint={endpoint}")

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(endpoint, headers=headers, json=payload, params=params, timeout=30.0)
            response.raise_for_status()
            formatted_response = format_search_response(response.json(), payload.get("fieldsToInclude", []))
            return formatted_response
        except httpx.HTTPStatusError as e:
            error_msg = f"HTTP {e.response.status_code}: {e.response.text}"
            logger.error(f"search_coveo HTTP error: {error_msg}")
            logger.error(f"Request details: endpoint={endpoint}, payload={json.dumps(payload)}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            return {"error": error_msg}
        except Exception as e:
            error_msg = f"Request failed: {str(e)}"
            logger.error(f"search_coveo exception: {error_msg}")
            logger.error(f"Exception type: {type(e).__name__}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            return {"error": error_msg}

async def retrieve_passages(query: str, number_of_passages: int = 5) -> Dict:
    """
    Retrieves passages from Coveo API.
    """
    search_context = SearchContext(q=query)
    endpoint = COVEO_PASSAGES_API_ENDPOINT.format(org_id=ORG_ID)
    
    is_oauth_token = search_context.bearer_token.startswith('x') and not search_context.bearer_token.startswith('xx')
    headers = {
        'Authorization': f'Bearer {search_context.bearer_token}',
        'Content-Type': 'application/json',
        'accept': 'application/json'
    }
    
    # Add organizationId in headers if using API Key
    if not is_oauth_token:
        headers['organizationId'] = search_context.organization_id
    
    # Only add organizationId as query parameter for OAuth tokens
    params = {}
    if is_oauth_token:
        params['organizationId'] = search_context.organization_id
    
    payload = {
        "query": search_context.q,
        "filter": search_context.filter,
        "maxPassages": number_of_passages,
        "localization": {
            "locale": search_context.locale,
            "timezone": search_context.timezone
        },
        "context": search_context.context or {},
        "additionalFields": search_context.additionalFields or [],
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(endpoint, headers=headers, json=payload, params=params, timeout=30.0)
            response.raise_for_status()
            data = response.json()
            formatted_passages = format_passage_retrieval_response(data.get('items', []))
            return formatted_passages
        except httpx.HTTPStatusError as e:
            error_msg = f"HTTP {e.response.status_code}: {e.response.text}"
            logger.error(f"passage_retrieval HTTP error: {error_msg}")
            logger.error(f"Request details: endpoint={endpoint}, query={query}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            return []
        except Exception as e:
            logger.error(f"passage_retrieval exception: {str(e)}")
            logger.error(f"Exception type: {type(e).__name__}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            return []

async def generate_answer(query: str) -> str:
    """
    Generates an answer using Coveo Answer API's streaming endpoint.
        
    Args:
        query (str): The question to answer.

    Returns:
        str: The generated answer or error message.
    """
    if not query:
        return "Error: Query cannot be empty"
    
    # Format the endpoint URL with organization ID and config ID
    endpoint = COVEO_ANSWER_API_ENDPOINT.format(
        org_id=ORG_ID,
        config_id=ANSWER_CONFIG_ID
    )
    
    headers = {
        'Authorization': f'Bearer {API_KEY}',
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'Accept-Language': 'en-US',
        'User-Agent': USER_AGENT
    }
    
    payload = {
        'q': query,
        'context': '',
        'pipelineRuleParameters': {
            'mlGenerativeQuestionAnswering': {
                'responseFormat': {
                    'contentFormat': ['text/markdown', 'text/plain']
                }
            }
        }
    }
    

    
    try:
        complete_answer = []
        citations = []

        async with httpx.AsyncClient() as client:
            async with client.stream('POST', endpoint, headers=headers, json=payload, timeout=60.0) as response:
                response.raise_for_status()
                
                async for line in response.aiter_lines():
                    if not line.strip() or not line.startswith('data:'):
                        continue
                    
                    # Extract the JSON data part
                    json_data = line.replace('data:', '').strip()
                    try:
                        data = json.loads(json_data)
                        payload_type = data.get('payloadType')
                        
                        # Process different types of responses
                        if payload_type == 'genqa.messageType':
                            payload = json.loads(data.get('payload', '{}'))
                            text_delta = payload.get('textDelta', '')
                            if text_delta:
                                complete_answer.append(text_delta)
                        
                        # Extract citations if available
                        elif payload_type == 'genqa.citationsType':
                            payload = json.loads(data.get('payload', '{}'))
                            citations = payload.get('citations', [])
                        
                        # Check for end of stream or errors
                        elif payload_type == 'genqa.endOfStreamType':
                            break
                    
                    except json.JSONDecodeError:
                        continue
        
        # Format the final answer
        answer_text = ''.join(complete_answer)
        
        if not answer_text:
            return "No answer could be generated for this query."
        
        # Add citations if available
        if citations:
            answer_text += "\n\nSources:\n"
            for i, citation in enumerate(citations, 1):
                title = citation.get('title', 'Unknown')
                uri = citation.get('uri', '')
                answer_text += f"{i}. [{title}]({uri})\n"
        
        return answer_text
    
    except httpx.HTTPStatusError as e:
        error_body = e.response.text if hasattr(e.response, 'text') else str(e)
        error_msg = f"HTTP {e.response.status_code}: {error_body}"
        logger.error(f"generate_answer HTTP error: {error_msg}")
        logger.error(f"Request details: endpoint={endpoint}, query={query}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise Exception(error_msg)
    except Exception as e:
        error_msg = f"Answer generation failed: {str(e)}"
        logger.error(f"generate_answer exception: {error_msg}")
        logger.error(f"Exception type: {type(e).__name__}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise Exception(error_msg)
