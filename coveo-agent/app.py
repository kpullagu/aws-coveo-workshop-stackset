# coveo-agent/app.py
import os
import json
import typing as t

from bedrock_agentcore.runtime import BedrockAgentCoreApp, BedrockAgentCoreContext
from strands import Agent, tool

from mcp_adapter import CoveoMCPAdapter

SYSTEM_PROMPT = """
You are **Coveo Support Assistant**, a helpful AI that provides accurate, well-formatted answers using only information from available tools.

## Core Principles

1. **Grounding**: Use ONLY information from tool outputs. Never make up information.
2. **Formatting**: Provide clean, well-structured answers in markdown format with proper headings, lists, and emphasis.
3. **Sources**: Sources will be automatically extracted from tool responses and displayed separately. Focus on the answer content.
4. **Clarity**: Be concise and direct. Lead with the answer, then provide supporting details.
5. **No Internal Tags**: NEVER include <thinking>, <reasoning>, or any XML-style tags in your response. Keep all reasoning internal.
6. **No Manual Citations**: Do NOT manually list sources in your response. They will be displayed automatically from the tool results.

## Response Format

### For Direct Questions (Single-Turn):
Provide a clear, direct answer with proper formatting. Sources will be displayed automatically.

Example:
```
## ACH Payment System

ACH stands for **Automated Clearing House**, a nationwide electronic payment network that facilitates fund transfers between financial institutions.

### Key Features:
- Processes transactions in batches
- Commonly used for direct deposits
- Ideal for bill payments and recurring transactions
- Lower cost compared to card transactions
```

### For Conversations (Multi-Turn):
Build on previous context and provide relevant information with clear structure.

Example:
```
Based on our previous discussion about payment systems, ACH is particularly useful for recurring payments.

### Why ACH for Recurring Payments?
- **Batch Processing**: Reduces per-transaction costs
- **Reliability**: Established network with high success rates
- **Automation**: Easy to set up recurring schedules
```

### When Clarification Needed:
Ask specific, clear questions without any tags.

Example:
```
I found information about vaccines, but I need more context to provide the most relevant answer. Are you asking about:
- Travel vaccines for specific destinations?
- Routine vaccination schedules?
- Vaccine requirements for a particular country?

Please let me know so I can provide accurate information.
```

## Available Tools

### answer_question(query)
- **Use for**: Direct factual questions, definitions, how-to queries
- **Returns**: Curated answer with citations from Coveo Answer API
- **Best for**: Single, focused questions with clear answers

### passage_retrieval(query, top_k)
- **Use for**: Detailed explanations, comparisons, multi-step processes
- **Returns**: Relevant passages with full context and metadata
- **Best for**: Complex questions requiring synthesis from multiple sources

### search_coveo(query, top_k)
- **Use for**: Broad exploration, finding multiple resources
- **Returns**: Ranked search results with excerpts
- **Best for**: Open-ended or exploratory queries

## Tool Selection Strategy

1. **Try answer_question first** for direct, factual questions
   - If answer is complete and confident → return it with sources
   - If answer is incomplete or low confidence → proceed to step 2

2. **Use passage_retrieval** for detailed explanations
   - Retrieve 5-8 passages
   - Synthesize information ONLY from retrieved passages
   - Include sources with titles and URLs

3. **Use search_coveo** for broad or exploratory queries
   - Get overview of available resources
   - Usually follow up with passage_retrieval for specific details

4. **If insufficient information**:
   - State what you found
   - Explain what's missing
   - Suggest how the user can refine their question

## Memory Usage (Multi-Turn Conversations)

When in a multi-turn conversation:
- **Remember context** from previous messages in the session
- **Reference previous answers** when relevant ("As I mentioned earlier...")
- **Build on prior information** rather than repeating
- **Track the conversation flow** to provide coherent responses
- **Remember topics discussed** so follow-up questions make sense
- **Ask for clarification** if the question is ambiguous given the context

### Important for Follow-up Questions:
- If the user asks a follow-up question (e.g., "How does it work?" after asking about ACH), you should:
  1. Recognize the topic from previous context (ACH)
  2. Call the appropriate tool again with the refined query
  3. Provide fresh information with new sources
  4. You may reference previous information but ALWAYS provide current sources

### Memory Limitations:
- Memory stores conversation context (topics, questions, answers)
- Memory does NOT store full source citations from previous turns
- For follow-up questions, ALWAYS call tools again to get fresh sources
- This ensures users always get current, complete citations

## Critical Rules

❌ **NEVER DO:**
- Include <thinking>, <reasoning>, or any XML-style tags in responses
- Expose internal reasoning or decision-making process
- Make up information not found in tool outputs
- Provide answers without sources

✅ **ALWAYS DO:**
- Provide clean, formatted markdown responses
- Include complete source citations with titles and URLs
- Ask clarifying questions when the query is ambiguous
- Use conversation context in multi-turn chats
- Keep responses concise and focused

## Source Citation Format

Always format sources as:
```
**Sources:**
- [Title](URL) - Project (if available)
- [Title](URL)
```

Ensure each source includes:
- Title (from tool output)
- Clickable URL
- Project name (if available)
"""

# AgentCore Runtime doesn't support environment variables in ContainerConfiguration
# So we read from SSM Parameter Store at startup
import boto3
import os

# Get region from environment or default to us-east-1
# AgentCore Runtime automatically sets AWS_REGION in the container
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')

# Set AWS_REGION for boto3 and Bedrock SDK
os.environ['AWS_REGION'] = AWS_REGION
os.environ['AWS_DEFAULT_REGION'] = AWS_REGION

ssm = boto3.client('ssm', region_name=AWS_REGION)
STACK_PREFIX = "workshop"  # Default stack prefix

def get_ssm_parameter(name, default=None):
    """Get parameter from SSM Parameter Store."""
    try:
        response = ssm.get_parameter(Name=name)
        return response['Parameter']['Value']
    except Exception as e:
        if default is not None:
            print(f"WARNING: Failed to get SSM parameter {name}, using default: {e}")
            return default
        print(f"ERROR: Failed to get SSM parameter {name}: {e}")
        raise

# Read configuration from SSM
REGION = get_ssm_parameter(f'/{STACK_PREFIX}/aws-region', default="us-east-1")
MODEL_ID = get_ssm_parameter(f'/{STACK_PREFIX}/coveo/bedrock-model-id', default="us.anthropic.claude-3-7-sonnet-20250219-v1:0")
MCP_RUNTIME_ARN = get_ssm_parameter(f'/{STACK_PREFIX}/coveo/mcp-runtime-arn')
MCP_URL = get_ssm_parameter(f'/{STACK_PREFIX}/coveo/mcp-url', default=None)

print(f"DEBUG: REGION={REGION}")
print(f"DEBUG: MODEL_ID={MODEL_ID}")
print(f"DEBUG: MCP_RUNTIME_ARN={MCP_RUNTIME_ARN}")

# Get Memory ID from environment variable (set by CloudFormation)
MEMORY_ID = os.environ.get('MEMORY_ID')
print(f"DEBUG: MEMORY_ID={MEMORY_ID}")

# Configure Bedrock Model Invocation Logging
try:
    bedrock_client = boto3.client('bedrock', region_name=REGION)
    log_group_name = f'/aws/bedrock/modelinvocations/{os.environ.get("AWS_STACK_NAME", "workshop-coveo-agent")}'
    
    bedrock_client.put_model_invocation_logging_configuration(
        loggingConfig={
            'cloudWatchConfig': {
                'logGroupName': log_group_name,
                'roleArn': os.environ.get('EXECUTION_ROLE_ARN', ''),  # Will be set by CloudFormation
                'largeDataDeliveryS3Config': {
                    'bucketName': '',  # Optional: S3 bucket for large payloads
                    'keyPrefix': ''
                }
            },
            'textDataDeliveryEnabled': True,
            'imageDataDeliveryEnabled': False,
            'embeddingDataDeliveryEnabled': False
        }
    )
    print(f"DEBUG: Model invocation logging configured to {log_group_name}")
except Exception as e:
    print(f"WARNING: Failed to configure model invocation logging: {e}")

# Initialize BedrockAgentCoreApp
app = BedrockAgentCoreApp()

# Initialize Memory Client for conversation history
from bedrock_agentcore.memory import MemoryClient

memory_client = None
if MEMORY_ID:
    try:
        memory_client = MemoryClient(region_name=REGION)
        print(f"DEBUG: Memory client initialized with memory_id={MEMORY_ID}")
    except Exception as e:
        print(f"WARNING: Failed to initialize memory client: {e}")
        memory_client = None

mcp = CoveoMCPAdapter(mcp_runtime_arn=MCP_RUNTIME_ARN, region=REGION, mcp_url=MCP_URL)

# ===== Tool wrappers with controls pass-through =====

@tool
def coveo_answer_question(query: str, answer_config_id: t.Optional[str] = None) -> str:
    """Get a curated single-turn answer from Coveo Answer API via MCP (prefer first)."""
    payload = {"query": query}
    if answer_config_id:
        payload["answer_config_id"] = answer_config_id
    # merge any agent-provided controls for "answer"
    extra = mcp.get_extra("answer")
    if isinstance(extra, dict):
        payload.update(extra)
    result = mcp.call_tool("answer_question", payload)
    return json.dumps(result, ensure_ascii=False)

@tool
def coveo_passage_retrieval(query: str, top_k: int = 8, filters: t.Optional[dict] = None) -> str:
    """Retrieve precise passages for synthesis and citations."""
    payload = {"query": query, "top_k": top_k}
    if filters:
        payload["filters"] = filters
    # merge any agent-provided controls for "passages" (e.g., additionalFields)
    extra = mcp.get_extra("passages")
    if isinstance(extra, dict):
        payload.update(extra)
    result = mcp.call_tool("passage_retrieval", payload)
    return json.dumps(result, ensure_ascii=False)

@tool
def coveo_search(query: str, top_k: int = 10, filters: t.Optional[dict] = None) -> str:
    """Perform broad recall when the query is underspecified or exploratory."""
    payload = {"query": query, "top_k": top_k}
    if filters:
        payload["filters"] = filters
    # merge any agent-provided controls for "search"
    extra = mcp.get_extra("search")
    if isinstance(extra, dict):
        payload.update(extra)
    result = mcp.call_tool("search_coveo", payload)
    return json.dumps(result, ensure_ascii=False)


def clean_response(text: str) -> str:
    """Remove thinking tags and clean up response for user display"""
    import re
    # Remove <thinking> tags and their content
    text = re.sub(r'<thinking>.*?</thinking>', '', text, flags=re.DOTALL | re.IGNORECASE)
    # Remove <reasoning> tags and their content
    text = re.sub(r'<reasoning>.*?</reasoning>', '', text, flags=re.DOTALL | re.IGNORECASE)
    # Remove any other XML-style tags
    text = re.sub(r'<[^>]+>.*?</[^>]+>', '', text, flags=re.DOTALL)
    # Clean up extra whitespace
    text = re.sub(r'\n\s*\n\s*\n+', '\n\n', text)
    return text.strip()

@app.entrypoint
def invoke(payload: dict, context: BedrockAgentCoreContext):
    # 1) Controls pass-through from UI/Lambda
    controls = payload.get("controls") or {}
    mcp.set_controls(controls)

    # 2) Extract session information for memory
    session_id = payload.get("session_id", "default_session")
    actor_id = payload.get("actor_id", payload.get("user_id", "default_user"))
    user_text = payload.get("text") or payload.get("prompt") or ""

    # 3) Retrieve relevant memories if available
    conversation_context = ""
    if memory_client and MEMORY_ID:
        try:
            # Retrieve memories for this session
            memories = memory_client.retrieve_memories(
                memory_id=MEMORY_ID,
                namespace=f"/summaries/{actor_id}/{session_id}",
                query=user_text
            )
            
            if memories and len(memories) > 0:
                conversation_context = "\n\n**Previous Context:**\n"
                for memory in memories[:3]:  # Use top 3 relevant memories
                    conversation_context += f"- {memory.get('content', '')}\n"
                print(f"DEBUG: Retrieved {len(memories)} memories for session {session_id}")
        except Exception as e:
            print(f"WARNING: Failed to retrieve memories: {e}")

    # 4) Build agent with policy & tools
    # Note: Region is configured via AWS_REGION environment variable, not passed to Agent
    agent = Agent(
        model=MODEL_ID,
        system_prompt=SYSTEM_PROMPT + conversation_context,
        tools=[coveo_answer_question, coveo_passage_retrieval, coveo_search],
    )

    result = agent(user_text)

    content = result.message.get("content", [{}])
    text = content[0].get("text") if content and isinstance(content, list) else str(result)
    
    # Clean response to remove any thinking tags
    text = clean_response(text)
    
    # 5) Extract sources from tool calls
    sources = []
    try:
        # Check if result has tool_calls or tool_use information
        if hasattr(result, 'tool_calls') and result.tool_calls:
            for tool_call in result.tool_calls:
                if hasattr(tool_call, 'result') and tool_call.result:
                    tool_result = tool_call.result
                    # Try to parse tool result as JSON
                    if isinstance(tool_result, str):
                        try:
                            import json
                            tool_data = json.loads(tool_result)
                            # Extract citations/results from tool response
                            if isinstance(tool_data, dict):
                                # From answer API
                                if 'citations' in tool_data:
                                    for citation in tool_data.get('citations', []):
                                        sources.append({
                                            'title': citation.get('title', ''),
                                            'url': citation.get('uri', citation.get('clickUri', citation.get('clickableuri', ''))),
                                            'project': citation.get('project', '')
                                        })
                                # From search/passages API
                                elif 'results' in tool_data:
                                    for result_item in tool_data.get('results', [])[:5]:  # Top 5 results
                                        sources.append({
                                            'title': result_item.get('title', ''),
                                            'url': result_item.get('clickUri', result_item.get('uri', '')),
                                            'project': result_item.get('raw', {}).get('project', '')
                                        })
                        except:
                            pass
        
        # Deduplicate sources by URL
        seen_urls = set()
        unique_sources = []
        for source in sources:
            if source['url'] and source['url'] not in seen_urls:
                seen_urls.add(source['url'])
                unique_sources.append(source)
        sources = unique_sources
        
        print(f"DEBUG: Extracted {len(sources)} sources from tool calls")
    except Exception as e:
        print(f"WARNING: Failed to extract sources: {e}")
    
    # 6) Store conversation in memory
    if memory_client and MEMORY_ID:
        try:
            memory_client.create_event(
                memory_id=MEMORY_ID,
                actor_id=actor_id,
                session_id=session_id,
                messages=[
                    (user_text, "USER"),
                    (text, "ASSISTANT")
                ]
            )
            print(f"DEBUG: Stored conversation in memory for session {session_id}")
        except Exception as e:
            print(f"WARNING: Failed to store memory: {e}")
    
    return {
        "response": text,
        "session_id": session_id,
        "sources": sources
    }

if __name__ == "__main__":
    app.run()
