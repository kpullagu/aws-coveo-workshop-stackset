# coveo-agent/app.py
import os
import json
import typing as t

from bedrock_agentcore.runtime import BedrockAgentCoreApp, BedrockAgentCoreContext
from strands import Agent, tool

from mcp_adapter import CoveoMCPAdapter

SYSTEM_PROMPT = """
You are **Coveo Finance Assistant**, a helpful AI that provides accurate, well-formatted answers about financial topics using only information from available tools.

## Core Principles

1. **Grounding**: Use ONLY information from tool outputs. Never make up information or URLs.
2. **Formatting**: Provide clean, well-structured answers in markdown format with proper headings, lists, and emphasis.
3. **Sources**: ALWAYS call tools for knowledge questions. Sources will be automatically extracted from tool responses and displayed separately. Focus on the answer content.
4. **Clarity**: Be concise and direct. Lead with the answer, then provide supporting details.
5. **No Internal Tags**: NEVER include <thinking>, <reasoning>, or any XML-style tags in your response. Keep all reasoning internal.
6. **No Manual Citations**: Do NOT manually list sources in your response. They will be displayed automatically from the tool results.
7. **CRITICAL**: For every knowledge question, you MUST call at least one tool (answer_question, passage_retrieval, or search_coveo). Never answer knowledge questions from memory alone.

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
I found information about retirement accounts, but I need more context to provide the most relevant answer. Are you asking about:
- Traditional IRA vs Roth IRA differences?
- 401(k) contribution limits?
- Early withdrawal penalties?

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
   - If answer is complete and confident → return it with sources and Always cite sources with titles and URLs from retrieved passages.
   - If answer is incomplete or low confidence → proceed to step 2

2. **Use passage_retrieval** for detailed explanations
   - Retrieve 5-8 passages
   - Synthesize information ONLY from retrieved passages
   - Always Include sources and cite sources with titles and URLs from retrieved passages.

3. **Use search_coveo** for broad or exploratory queries
   - Get overview of available resources
   - Usually follow up with passage_retrieval for specific details

4. **If insufficient information**:
   - State what you found
   - Explain what's missing
   - Suggest how the user can refine their question

## Memory Usage (Multi-Turn and Cross-Session)

You have access to conversation memory both within the current session and across previous sessions.

### Question Type Detection

Before calling tools, determine if the question is about:

**1. Memory/History Questions** (DO NOT call tools):
- "What did we discuss?" / "Remind me about..." / "What were we talking about?"
- "What did I ask last time?" / "What topics have we covered?"
- Action: Answer from conversation memory WITHOUT calling tools

**2. Knowledge Questions** (CALL tools):
- "What is ACH?" / "How do 401k plans work?" / "Tell me about Roth IRAs"
- Action: Call appropriate tool (answer_question, passage_retrieval, or search_coveo)

### Memory Capabilities

**Within-Session Memory:**
- Remember all exchanges in the current conversation
- Track conversation flow and context
- Reference previous answers when relevant

**Cross-Session Memory:**
- Recall topics from previous conversations (days/weeks ago)
- Remember user preferences and interests
- Provide personalized responses based on history

### Using Memory Effectively

**For Memory Questions:**
```
User: "What did we discuss last time?"
You: "In our previous session, we discussed ACH payment systems, including 
      how they work for direct deposits and bill payments."
```
Do NOT call tools - answer from memory.

**For Follow-up Knowledge Questions:**
```
User: "What is ACH?"
You: [Call answer_question or passage_retrieval] → Provide answer with sources

User: "How does it compare to wire transfers?"
You: [Call passage_retrieval again] → Provide comparison with NEW sources
```
Always call tools for knowledge questions, even if topic was discussed before.

### Memory Guidelines

- **Reference context**: "As we discussed earlier..." or "Building on our previous conversation..."
- **Personalize**: Adapt responses based on user's interests and previous questions
- **Fresh sources**: For knowledge questions, ALWAYS call tools to get current sources
- **Don't repeat**: If user asks same question, acknowledge and provide concise answer
- **Clarify ambiguity**: Use context to understand vague follow-ups ("How does it work?" → understand "it" from context)

### Important Notes

- Memory stores conversation summaries (topics, questions, general answers)
- Memory does NOT store full source citations from previous turns
- For knowledge questions, ALWAYS call tools to get fresh, complete sources
- This ensures users always get current, accurate citations

## Critical Rules

❌ **NEVER DO:**
- Include <thinking>, <reasoning>, or any XML-style tags in responses
- Expose internal reasoning or decision-making process
- Make up information not found in tool outputs
- Provide answers without sources
- Invent URLs or permanentids.

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
MODEL_ID = get_ssm_parameter(f'/{STACK_PREFIX}/coveo/bedrock-model-id', default="us.amazon.nova-lite-v1:0")
MCP_RUNTIME_ARN = get_ssm_parameter(f'/{STACK_PREFIX}/coveo/mcp-runtime-arn')
MCP_URL = get_ssm_parameter(f'/{STACK_PREFIX}/coveo/mcp-url', default=None)

print(f"DEBUG: REGION={REGION}")
print(f"DEBUG: MODEL_ID={MODEL_ID}")
print(f"DEBUG: MCP_RUNTIME_ARN={MCP_RUNTIME_ARN}")

# Get Memory ID from environment variable (set by CloudFormation)
MEMORY_ID = os.environ.get('MEMORY_ID')
print(f"DEBUG: MEMORY_ID={MEMORY_ID}")

# NOTE: Bedrock Model Invocation Logging is configured via enable-bedrock-model-invocation-logging.sh
# Do not configure it here to avoid conflicts and permission issues

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

def get_stable_actor_id(payload: dict, context: BedrockAgentCoreContext) -> str:
    """
    Extract stable user identity from Cognito JWT token.
    
    Priority:
    1. actor_id from payload (if explicitly provided)
    2. Extract from Cognito JWT token in context
    3. user_id from payload
    4. Default to 'anonymous'
    """
    # Check if actor_id is explicitly provided
    if payload.get("actor_id"):
        return payload["actor_id"]
    
    # Try to extract from Cognito JWT token
    try:
        # AgentCore context may have identity information
        if hasattr(context, 'identity') and context.identity:
            identity = context.identity
            # Try common JWT claims
            if hasattr(identity, 'sub'):
                return identity.sub
            if hasattr(identity, 'cognito_username'):
                return identity.cognito_username
            if hasattr(identity, 'username'):
                return identity.username
    except Exception as e:
        print(f"WARNING: Failed to extract identity from context: {e}")
    
    # Fallback to user_id from payload
    if payload.get("user_id"):
        return payload["user_id"]
    
    # Default
    return "anonymous"

@app.entrypoint
def invoke(payload: dict, context: BedrockAgentCoreContext):
    # 1) Controls pass-through from UI/Lambda
    controls = payload.get("controls") or {}
    mcp.set_controls(controls)

    # 2) Extract session information for memory
    session_id = payload.get("session_id", "default_session")
    actor_id = get_stable_actor_id(payload, context)
    user_text = payload.get("text") or payload.get("prompt") or ""
    end_session = payload.get("end_session", False)
    
    # OBSERVABILITY: Log session start with correlation ID
    print(f"OBSERVABILITY session_id={session_id} actor_id={actor_id} event=session_start end_session={end_session}")
    print(f"OBSERVABILITY session_id={session_id} event=request_received text_length={len(user_text)}")
    
    # Set session ID in MCP adapter for correlation
    mcp.set_session_id(session_id)

    # 3) Handle session end request
    if end_session:
        print(f"OBSERVABILITY session_id={session_id} actor_id={actor_id} event=session_end_requested")
        
        # Write final session_end event for summarization
        if memory_client and MEMORY_ID:
            try:
                memory_client.create_event(
                    memory_id=MEMORY_ID,
                    actor_id=actor_id,
                    session_id=session_id,
                    messages=[
                        ("Session ended by user", "SYSTEM")
                    ],
                    metadata={"type": "session_end"}
                )
                print(f"DEBUG: Wrote session_end event for session {session_id}")
                print(f"OBSERVABILITY session_id={session_id} event=session_end_complete")
            except Exception as e:
                print(f"WARNING: Failed to write session_end event: {e}")
        
        # Return acknowledgment
        return {
            "response": "Session ended successfully. Your conversation has been saved.",
            "session_id": session_id,
            "sources": []
        }
    
    # 4) Retrieve relevant memories if available (cross-session memory)
    conversation_context = ""
    if memory_client and MEMORY_ID:
        try:
            # Retrieve memories from all sessions for this actor
            memories = memory_client.retrieve_memories(
                memory_id=MEMORY_ID,
                namespace=f"/summaries/{actor_id}",
                query=user_text
            )
            
            if memories and len(memories) > 0:
                conversation_context = "\n\n**Previous Context:**\n"
                for memory in memories[:3]:  # Use top 3 relevant memories
                    conversation_context += f"- {memory.get('content', '')}\n"
                print(f"DEBUG: Retrieved {len(memories)} memories for actor {actor_id}")
        except Exception as e:
            print(f"WARNING: Failed to retrieve memories: {e}")

    # 5) Build agent with policy & tools
    # Note: Region is configured via AWS_REGION environment variable, not passed to Agent
    print(f"OBSERVABILITY session_id={session_id} event=tool_plan_start text='{user_text[:120]}'")
    
    agent = Agent(
        model=MODEL_ID,
        system_prompt=SYSTEM_PROMPT + conversation_context,
        tools=[coveo_answer_question, coveo_passage_retrieval, coveo_search],
    )

    result = agent(user_text)
    
    print(f"OBSERVABILITY session_id={session_id} event=tool_plan_done")

    content = result.message.get("content", [{}])
    text = content[0].get("text") if content and isinstance(content, list) else str(result)
    
    # Clean response to remove any thinking tags
    text = clean_response(text)
    
    # 6) Extract sources from tool calls and log tool usage
    sources = []
    tools_used = []
    try:
        # Check if result has tool_calls or tool_use information
        if hasattr(result, 'tool_calls') and result.tool_calls:
            # OBSERVABILITY: Log which tools were called
            tools_used = [tc.name if hasattr(tc, 'name') else str(tc) for tc in result.tool_calls]
            print(f"OBSERVABILITY session_id={session_id} event=tools_selected tools={','.join(tools_used)}")
            
            for tool_call in result.tool_calls:
                tool_name = tool_call.name if hasattr(tool_call, 'name') else 'unknown'
                print(f"DEBUG: Processing tool call: {tool_name}")
                
                if hasattr(tool_call, 'result') and tool_call.result:
                    tool_result = tool_call.result
                    print(f"DEBUG: Tool result type: {type(tool_result)}")
                    
                    # Try to parse tool result as JSON
                    if isinstance(tool_result, str):
                        try:
                            tool_data = json.loads(tool_result)
                            print(f"DEBUG: Parsed tool data keys: {tool_data.keys() if isinstance(tool_data, dict) else 'not a dict'}")
                            
                            # Extract citations/results from tool response
                            if isinstance(tool_data, dict):
                                # From answer API - check for citations
                                if 'citations' in tool_data and tool_data['citations']:
                                    print(f"DEBUG: Found {len(tool_data['citations'])} citations in answer API response")
                                    for citation in tool_data.get('citations', []):
                                        url = citation.get('uri') or citation.get('clickUri') or citation.get('clickableuri', '')
                                        title = citation.get('title', 'Untitled')
                                        if url:  # Only add if URL exists
                                            sources.append({
                                                'title': title,
                                                'url': url,
                                                'project': citation.get('project', '')
                                            })
                                            print(f"DEBUG: Added citation: {title[:50]}... -> {url[:50]}...")
                                
                                # From passages API - check for passages/items
                                elif 'passages' in tool_data and tool_data['passages']:
                                    print(f"DEBUG: Found {len(tool_data['passages'])} passages")
                                    for passage in tool_data.get('passages', [])[:8]:  # Top 8 passages
                                        url = passage.get('uri') or passage.get('clickUri') or passage.get('clickableuri', '')
                                        title = passage.get('title', 'Untitled')
                                        if url:  # Only add if URL exists
                                            sources.append({
                                                'title': title,
                                                'url': url,
                                                'project': passage.get('project', '')
                                            })
                                            print(f"DEBUG: Added passage: {title[:50]}... -> {url[:50]}...")
                                
                                # From search API - check for results
                                elif 'results' in tool_data and tool_data['results']:
                                    print(f"DEBUG: Found {len(tool_data['results'])} search results")
                                    for result_item in tool_data.get('results', [])[:8]:  # Top 8 results
                                        # Handle both direct fields and nested raw fields
                                        url = result_item.get('clickUri') or result_item.get('uri', '')
                                        title = result_item.get('title', 'Untitled')
                                        project = result_item.get('project', '')
                                        
                                        # Try raw field if not found at top level
                                        if not url and 'raw' in result_item:
                                            url = result_item['raw'].get('clickableuri', '')
                                        if not project and 'raw' in result_item:
                                            project = result_item['raw'].get('project', '')
                                        
                                        if url:  # Only add if URL exists
                                            sources.append({
                                                'title': title,
                                                'url': url,
                                                'project': project
                                            })
                                            print(f"DEBUG: Added search result: {title[:50]}... -> {url[:50]}...")
                                
                                else:
                                    print(f"WARNING: Tool data has no recognized source fields. Keys: {list(tool_data.keys())}")
                        except json.JSONDecodeError as e:
                            print(f"WARNING: Failed to parse tool result as JSON: {e}")
                            print(f"DEBUG: Tool result preview: {tool_result[:200]}...")
                        except Exception as e:
                            print(f"WARNING: Error processing tool result: {e}")
                    else:
                        print(f"DEBUG: Tool result is not a string, type: {type(tool_result)}")
        else:
            print(f"WARNING: No tool_calls found in result. Result type: {type(result)}")
            print(f"DEBUG: Result attributes: {dir(result)}")
        
        # Deduplicate sources by URL
        seen_urls = set()
        unique_sources = []
        for source in sources:
            url = source.get('url', '')
            if url and url not in seen_urls:
                seen_urls.add(url)
                unique_sources.append(source)
        sources = unique_sources
        
        print(f"INFO: Extracted {len(sources)} unique sources from {len(tools_used)} tool calls")
        if len(sources) == 0 and len(tools_used) > 0:
            print(f"WARNING: Tools were called but no sources were extracted! This is a bug.")
    except Exception as e:
        print(f"ERROR: Failed to extract sources: {e}")
        import traceback
        traceback.print_exc()
    
    # 7) Store conversation in memory
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
    
    # OBSERVABILITY: Log session completion
    print(f"OBSERVABILITY session_id={session_id} event=session_complete sources_count={len(sources)} tools_used={','.join(tools_used) if tools_used else 'none'}")
    
    # VALIDATION: Warn if tools were called but no sources extracted
    if len(tools_used) > 0 and len(sources) == 0:
        print(f"CRITICAL WARNING: Tools were called ({tools_used}) but NO sources were extracted!")
        print(f"CRITICAL WARNING: This means citations will not be displayed to the user.")
        print(f"CRITICAL WARNING: Check tool response format and source extraction logic.")
    
    # VALIDATION: Ensure all sources have valid URLs
    valid_sources = []
    for source in sources:
        if source.get('url') and source.get('url').startswith('http'):
            valid_sources.append(source)
        else:
            print(f"WARNING: Filtered out invalid source: {source}")
    
    if len(valid_sources) < len(sources):
        print(f"WARNING: Filtered {len(sources) - len(valid_sources)} sources with invalid URLs")
    
    return {
        "response": text,
        "session_id": session_id,
        "sources": valid_sources
    }

if __name__ == "__main__":
    app.run()
