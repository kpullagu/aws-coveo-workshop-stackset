import json
from typing import Any, Dict
import json
import logging
import sys
from typing import Any, Dict
from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP
from coveo_api import make_coveo_request, retrieve_passages, generate_answer

# Configure detailed logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)

logger.info("="*70)
logger.info("MCP Server Starting...")
logger.info("="*70)

load_dotenv()

logger.info("Initializing FastMCP with host=0.0.0.0, stateless_http=True")
mcp = FastMCP(host="0.0.0.0", stateless_http=True)
logger.info("FastMCP initialized successfully")

@mcp.tool()
async def search_coveo(query: str, numberOfResults: int = 5) -> Dict[str, Any]:
    """
    Use search_coveo when the goal is to retrieve metadata, titles, or URLs related to documents.
    Ideal for exploring information broadly, navigating multiple sources, or presenting lists of content without needing the content itself.
    
    Args:
        query (str): The search query.
        numberOfResults (int, optional): How many results to retrieve. Default: 5.
    
    Returns:
        Dict[str, Any]: Dictionary with 'results' key containing JSON string of search results, or 'error'/'message' key.
    """
    try:
        logger.info(f"search_coveo called: query='{query}', numberOfResults={numberOfResults}")
        payload = {
            "q": query,
            "numberOfResults": numberOfResults,
            "fieldsToExclude": [
                "rankingInfo"
            ],
            "fieldsToInclude": [
                "title",
                "uri",
                "objecttype",
                "collection",
                "source",
                "filetype",
                "project",
                "documenttype",
                "infobox_type",
                "categories",
                "data",
                "clickableuri",
                "summary",
                "body",
                "excerpt",
                "printableUri",
                "clickUri"
            ],
            "excerptLength": 500,
            "debugRankingInformation": False
        }
        data = await make_coveo_request(payload)
        
        if data and "error" not in data:
            if "results" in data and data["results"]:
                # Convert results list to JSON string for MCP compatibility
                return {"results": json.dumps(data["results"])}
            return {"message": "No results found for this query."}
        return {"error": data.get('error', 'Unknown error occurred')}
    except Exception as e:
        logger.error(f"search_coveo tool exception: {str(e)}")
        logger.error(f"Exception type: {type(e).__name__}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return {"error": f"Tool execution failed: {str(e)}"}

@mcp.tool()
async def passage_retrieval(query: str, numberOfPassages: int = 5) -> Dict[str, Any]:
    """
    Use passage_retrieval to extract highly relevant text snippets from documents.
    Useful when building answers, summaries, or even new documents from source material.
    Choose this tool when you need accurate, content-rich inputs to support generation beyond what a single answer can provide.
    
    Args:
        query (str): The search query.
        numberOfPassages (int, optional): How many passages to retrieve. Default: 5. Maximum: 20.
    
    Returns:
        Dict[str, Any]: Dictionary with 'passages' key containing JSON string of passages, or 'error'/'message' key.
    """
    try:
        if not query:
            return {"error": "Query cannot be empty"}
        
        passages = await retrieve_passages(query=query, number_of_passages=numberOfPassages)
        
        if not passages:
            return {"message": "No passages found for this query."}
        
        # Convert passages list to JSON string for MCP compatibility
        return {"passages": json.dumps(passages)}
    except Exception as e:
        logger.error(f"passage_retrieval tool exception: {str(e)}")
        logger.error(f"Exception type: {type(e).__name__}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return {"error": f"Tool execution failed: {str(e)}"}

@mcp.tool()
async def answer_question(query: str) -> Dict[str, Any]:
    """
    Use answer_question when the query requires a complete, consistent, and well-structured answer.
    This tool uses a prompt-engineered LLM, combining passages and documents, with safeguards to reduce hallucinations, ensure factual accuracy, and enforce security constraints.
    Designed for delivering clear, direct answers that are ready to consume.
    
    Args:
        query (str): The question to answer.
    
    Returns:
        Dict[str, Any]: The generated answer with citations or error message.
    """
    try:
        if not query:
            return {"error": "Query cannot be empty"}
        
        answer = await generate_answer(query)
        return {"answer": answer}
    except Exception as e:
        logger.error(f"answer_question tool exception: {str(e)}")
        logger.error(f"Exception type: {type(e).__name__}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return {"error": f"Tool execution failed: {str(e)}"}

if __name__ == "__main__":
    logger.info("="*70)
    logger.info("Starting MCP server with streamable-http transport")
    logger.info("Server will be available at: http://0.0.0.0:8000/mcp")
    logger.info("Registered tools: search_coveo, passage_retrieval, answer_question")
    logger.info("="*70)
    
    try:
        mcp.run(transport="streamable-http")
    except Exception as e:
        logger.error(f"Failed to start MCP server: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
