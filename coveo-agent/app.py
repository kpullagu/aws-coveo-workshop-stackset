import json
import os
import re
import threading
import typing as t
from contextvars import ContextVar

import boto3
from bedrock_agentcore.memory import MemoryClient
from bedrock_agentcore.runtime import BedrockAgentCoreApp, BedrockAgentCoreContext
from strands import Agent, tool

from memory.session import get_memory_query_manager, get_memory_session_manager
from mcp_adapter import CoveoMCPAdapter, MCPToolError

SYSTEM_PROMPT = """
You are **Coveo Finance Assistant**, a helpful AI that answers financial questions using Coveo Hosted MCP tools and conversation memory.

## CRITICAL RULES — NEVER VIOLATE

- **NEVER** output `<thinking>`, `<reasoning>`, or any XML/HTML-style tags. Respond with clean text and markdown only.
- **NEVER** answer a knowledge question using your own training knowledge. If all tools fail, say the tools could not retrieve an answer and suggest the user rephrase or try again.
- **NEVER** hallucinate or fabricate facts, URLs, or citations. Only use information returned by tools.

## Core Principles

1. **Grounding**: Use ONLY information returned by tools for knowledge questions.
2. **Formatting**: Respond with clean markdown suitable for HTML display. No XML tags of any kind.
3. **Tool Use**: For every knowledge question, call at least one tool. If the first tool fails, try a different tool before giving up.
4. **Memory**: Use active conversation context freely. Same-session context is authoritative.
5. **Sources**: Do not manually add a sources section. Sources are extracted from tool responses and displayed separately.

## Tool Selection and Fallback

### answer_tool(query)
- Use for direct factual questions, definitions, or concise how-to answers.
- Returns an RGA answer grounded in indexed content.

### passage_tool(query, top_k)
- Use for deeper explanations, comparisons, and multi-step questions.
- Returns relevant passages for synthesis.

### search_tool(query, top_k)
- Use for broad discovery or exploratory questions.
- Returns ranked search results.
- **This is also the fallback tool.** If answer_tool or passage_tool returns an error, call search_tool next.

### fetch_tool(item_id)
- Use when the user asks for a specific known item by unique identifier or when another tool surfaces a specific identifier you need to inspect directly.
- Returns the full content for one item.

### Fallback Strategy
If a tool returns an error message (e.g., "No answer was generated" or "Error executing Tool"):
1. **Do NOT answer from your own knowledge.** Instead, try a different tool.
2. Preferred fallback order: answer_tool → search_tool, passage_tool → search_tool.
3. If search_tool also fails, tell the user plainly that the tools could not retrieve an answer and suggest rephrasing.

## Memory Rules

### Memory/History questions
- Examples: "What did we discuss earlier?", "What did I ask last time?", "Remind me what we talked about."
- Do NOT call tools for these questions.
- Your conversation history is automatically loaded. Look at the messages in this conversation to answer recall questions.
- If cross-session context was injected (inside `<user_context>` tags), use it to answer questions about previous sessions.
- If no previous context is available, say that plainly and invite the user to ask a new question.

### Knowledge questions
- Examples: "What is ACH?", "How do 401(k) plans work?", "Compare Roth IRA and traditional IRA."
- Always call tools.
- Use current tool output even if the topic appeared in earlier conversations.

## Response Style

- Lead with the answer.
- Use short sections and bullets when helpful.
- Do not add generic recommendations, disclaimers, external websites, or next steps unless they are supported by the tool output.
- Ask a clarifying question only when the request is ambiguous enough that tool use would likely be wrong.
- If tools do not provide enough information, say so plainly and explain what is missing.
"""

HOSTED_MCP_TOOLS = {
    "answer": "answer_tool",
    "fetch": "fetch_tool",
    "passage": "passage_tool",
    "search": "search_tool",
}

TOOL_PAYLOADS: ContextVar[list[dict]] = ContextVar("tool_payloads", default=[])
TOOL_PAYLOADS_BY_SESSION: dict[str, list[dict]] = {}
TOOL_PAYLOADS_LOCK = threading.Lock()

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
os.environ["AWS_REGION"] = AWS_REGION
os.environ["AWS_DEFAULT_REGION"] = AWS_REGION

STACK_PREFIX = os.environ.get("STACK_PREFIX", "workshop")
ssm = boto3.client("ssm", region_name=AWS_REGION)


def get_ssm_parameter(name: str, default: t.Optional[str] = None, with_decryption: bool = False) -> t.Optional[str]:
    try:
        response = ssm.get_parameter(Name=name, WithDecryption=with_decryption)
        return response["Parameter"]["Value"]
    except Exception as exc:
        if default is not None:
            print(f"WARNING: Failed to get SSM parameter {name}, using default: {exc}")
            return default
        print(f"ERROR: Failed to get SSM parameter {name}: {exc}")
        raise


REGION = get_ssm_parameter(f"/{STACK_PREFIX}/aws-region", default=AWS_REGION)
MODEL_ID = get_ssm_parameter(
    f"/{STACK_PREFIX}/coveo/bedrock-model-id",
    default="us.amazon.nova-lite-v1:0",
)
HOSTED_MCP_ENDPOINT = get_ssm_parameter(f"/{STACK_PREFIX}/coveo/hosted-mcp-endpoint")
HOSTED_MCP_AUTH_MODE = get_ssm_parameter(
    f"/{STACK_PREFIX}/coveo/hosted-mcp-auth-mode",
    default="anonymous_api_key",
)
HOSTED_MCP_API_KEY = get_ssm_parameter(
    f"/{STACK_PREFIX}/coveo/hosted-mcp-api-key",
    with_decryption=True,
)
HOSTED_MCP_CONFIG_NAME = get_ssm_parameter(
    f"/{STACK_PREFIX}/coveo/hosted-mcp-config-name",
    default="Workshop-MCP-server",
)
HOSTED_MCP_SEARCH_HUB = get_ssm_parameter(
    f"/{STACK_PREFIX}/coveo/hosted-mcp-search-hub",
    default="MCP_Workshop-MCP-server",
)

print(f"DEBUG: STACK_PREFIX={STACK_PREFIX}")
print(f"DEBUG: REGION={REGION}")
print(f"DEBUG: MODEL_ID={MODEL_ID}")
print(f"DEBUG: HOSTED_MCP_CONFIG_NAME={HOSTED_MCP_CONFIG_NAME}")
print(f"DEBUG: HOSTED_MCP_SEARCH_HUB={HOSTED_MCP_SEARCH_HUB}")
print(f"DEBUG: HOSTED_MCP_ENDPOINT={HOSTED_MCP_ENDPOINT}")

MEMORY_ID = os.environ.get("MEMORY_ID")
print(f"DEBUG: MEMORY_ID={MEMORY_ID}")

app = BedrockAgentCoreApp()

memory_client: t.Optional[MemoryClient] = None
if MEMORY_ID:
    try:
        memory_client = MemoryClient(region_name=REGION)
        print(f"DEBUG: Memory client initialized with memory_id={MEMORY_ID}")
    except Exception as exc:
        print(f"WARNING: Failed to initialize memory client: {exc}")
        memory_client = None

mcp = CoveoMCPAdapter(
    endpoint=HOSTED_MCP_ENDPOINT,
    auth_mode=HOSTED_MCP_AUTH_MODE,
    api_key=HOSTED_MCP_API_KEY,
    region=REGION,
)
try:
    mcp.discover_tools()
except Exception as exc:
    print(f"WARNING: Hosted MCP tool discovery failed during startup: {exc}")


def normalize_result(raw_result: t.Any) -> dict:
    if isinstance(raw_result, str):
        try:
            raw_result = json.loads(raw_result)
        except json.JSONDecodeError:
            return {"text": raw_result}

    if not isinstance(raw_result, dict):
        return {"value": raw_result}

    normalized = dict(raw_result)

    answer = normalized.get("answer")
    if isinstance(answer, dict):
        if "answer" in answer and "answer" not in normalized:
            normalized["answer"] = answer.get("answer")
        if "citations" in answer and "citations" not in normalized:
            normalized["citations"] = answer.get("citations")

    if "result" in normalized and isinstance(normalized["result"], dict):
        result_block = normalized["result"]
        for key in ("answer", "citations", "results", "passages", "document"):
            if key in result_block and key not in normalized:
                normalized[key] = result_block[key]

    if "items" in normalized and "results" not in normalized and isinstance(normalized["items"], list):
        normalized["results"] = normalized["items"]

    if "item" in normalized and "document" not in normalized:
        normalized["document"] = normalized["item"]

    if "answer" not in normalized:
        for key in ("generatedAnswer", "answerText", "response", "text"):
            value = normalized.get(key)
            if isinstance(value, str) and value:
                normalized["answer"] = value
                break

    return normalized


def record_tool_payload(payload: dict) -> None:
    current_payloads = TOOL_PAYLOADS.get()
    TOOL_PAYLOADS.set([*current_payloads, payload])
    session_id = getattr(mcp, "_session_id", None)
    if session_id:
        with TOOL_PAYLOADS_LOCK:
            TOOL_PAYLOADS_BY_SESSION.setdefault(session_id, []).append(payload)


def normalize_document_result(raw_result: t.Any) -> dict:
    normalized = normalize_result(raw_result)
    if "document" not in normalized and isinstance(raw_result, dict):
        normalized["document"] = raw_result
    return normalized


def build_sources_from_payload(tool_data: dict) -> list[dict]:
    sources: list[dict] = []

    def add_source(title: str, url: str, project: str = "") -> None:
        if url:
            sources.append({"title": title or "Untitled", "url": url, "project": project or ""})

    for citation in tool_data.get("citations", []) or []:
        if isinstance(citation, dict):
            add_source(
                citation.get("title", "Untitled"),
                citation.get("url") or citation.get("uri") or citation.get("clickUri") or citation.get("clickableuri", ""),
                citation.get("project", ""),
            )

    for passage in tool_data.get("passages", []) or []:
        if isinstance(passage, dict):
            add_source(
                passage.get("title", "Untitled"),
                passage.get("url") or passage.get("uri") or passage.get("clickUri") or passage.get("clickableuri", ""),
                passage.get("project", ""),
            )

    for result_item in tool_data.get("results", []) or []:
        if isinstance(result_item, dict):
            raw = result_item.get("raw", {}) if isinstance(result_item.get("raw"), dict) else {}
            add_source(
                result_item.get("title", "Untitled"),
                result_item.get("url") or result_item.get("clickUri") or result_item.get("uri") or raw.get("clickableuri", ""),
                result_item.get("project") or raw.get("project", ""),
            )

    document = tool_data.get("document")
    if isinstance(document, dict):
        raw = document.get("raw", {}) if isinstance(document.get("raw"), dict) else {}
        add_source(
            document.get("title", "Untitled"),
            document.get("url") or document.get("clickUri") or document.get("uri") or raw.get("clickableuri", ""),
            document.get("project") or raw.get("project", ""),
        )

    unique_sources = []
    seen_urls = set()
    for source in sources:
        url = source.get("url", "")
        if url and url not in seen_urls:
            seen_urls.add(url)
            unique_sources.append(source)
    return unique_sources


def is_memory_history_question(text: str) -> bool:
    normalized = text.lower()
    has_time_marker = any(marker in normalized for marker in ("earlier", "previous", "last time", "last session", "before"))
    has_conversation_marker = any(
        marker in normalized
        for marker in ("discuss", "talk", "conversation", "chat", "ask", "asked", "covered", "question")
    )
    if has_time_marker and has_conversation_marker:
        return True

    memory_markers = (
        "what did we discuss",
        "what did i ask",
        "what was my previous question",
        "what was my last question",
        "what were we talking about",
        "remind me what",
        "previous conversation",
        "earlier conversation",
        "last session",
    )
    return any(marker in normalized for marker in memory_markers)


def is_previous_question_query(text: str) -> bool:
    normalized = text.lower()
    markers = (
        "what was my previous question",
        "what was my last question",
        "what did i ask",
        "previous question",
        "last question",
    )
    return any(marker in normalized for marker in markers)


def memory_content_to_text(memory: t.Any) -> str:
    content = memory.get("content") if isinstance(memory, dict) else memory
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, dict):
        for key in ("text", "summary", "content"):
            value = content.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        return json.dumps(content, ensure_ascii=False, sort_keys=True)
    if content is None:
        return ""
    return str(content).strip()


def retrieve_fallback_sources(query: str, limit: int = 5) -> list[dict]:
    if not query.strip() or is_memory_history_question(query):
        return []

    payload = {"query": query, "top_k": limit}
    extra = mcp.get_extra(HOSTED_MCP_TOOLS["search"])
    if isinstance(extra, dict):
        payload.update(extra)

    try:
        raw_result = mcp.call_tool(HOSTED_MCP_TOOLS["search"], payload)
        normalized = normalize_result(raw_result)
        sources = build_sources_from_payload(normalized)
        print(f"OBSERVABILITY event=fallback_sources count={len(sources)}")
        return sources
    except Exception as exc:
        print(f"WARNING: Failed to retrieve fallback sources: {exc}")
        return []


def clean_history_text(text: str) -> str:
    text = clean_response(text)
    text = re.sub(r"^Answer this question concisely:\s*", "", text, flags=re.IGNORECASE).strip()
    text = re.sub(r"\s+", " ", text)
    return text


def extract_messages_from_memory_event(event: dict) -> list[tuple[str, str]]:
    payload = event.get("payload") or event.get("eventPayload") or []
    if isinstance(payload, dict):
        payload = [payload]

    messages: list[tuple[str, str]] = []
    for item in payload if isinstance(payload, list) else []:
        if not isinstance(item, dict):
            continue
        conversational = item.get("conversational")
        if not isinstance(conversational, dict):
            continue

        role = str(conversational.get("role") or "").upper()
        raw_text = conversational.get("content", {}).get("text", "")
        if not raw_text:
            continue

        message_text = ""
        try:
            decoded = json.loads(raw_text)
            message = decoded.get("message", {}) if isinstance(decoded, dict) else {}
            role = str(message.get("role") or role).upper()
            for content_item in message.get("content", []) or []:
                if isinstance(content_item, dict) and isinstance(content_item.get("text"), str):
                    message_text += content_item["text"]
        except json.JSONDecodeError:
            message_text = raw_text

        message_text = clean_history_text(message_text)
        if role in {"USER", "ASSISTANT"} and message_text:
            messages.append((role, message_text))

    return messages


def get_session_messages(actor_id: str, session_id: str, limit: int = 40) -> list[tuple[str, str]]:
    if not memory_client or not MEMORY_ID:
        return []

    try:
        events = memory_client.list_events(
            memory_id=MEMORY_ID,
            actor_id=actor_id,
            session_id=session_id,
            max_results=limit,
            include_payload=True,
        )
    except Exception as exc:
        print(f"WARNING: Failed to list memory events for session {session_id}: {exc}")
        return []

    messages: list[tuple[str, str]] = []
    for event in reversed(events or []):
        messages.extend(extract_messages_from_memory_event(event))

    return messages


def list_recent_sessions(actor_id: str, current_session_id: str, limit: int = 8) -> list[dict]:
    if not memory_client or not MEMORY_ID or not hasattr(memory_client, "gmdp_client"):
        print(f"DEBUG: list_recent_sessions - memory_client not available")
        return []

    try:
        # Request more sessions than needed because API may not return them in recency order
        # We'll sort client-side and take the most recent 'limit' sessions
        response = memory_client.gmdp_client.list_sessions(
            memoryId=MEMORY_ID,
            actorId=actor_id,
            maxResults=50,  # Get many sessions to ensure we find the truly most recent ones
        )
    except Exception as exc:
        print(f"WARNING: Failed to list sessions for actor {mask_identifier(actor_id)}: {exc}")
        return []

    all_sessions = response.get("sessionSummaries", []) or []
    print(f"DEBUG: list_recent_sessions - found {len(all_sessions)} total sessions for actor {mask_identifier(actor_id)}")

    for i, sess in enumerate(all_sessions[:5]):
        sess_id = sess.get("sessionId", "unknown")
        created = sess.get("createdAt", "unknown")
        is_current = sess_id == current_session_id
        print(f"DEBUG: session[{i}] id={sess_id[:16]}... created={created} is_current={is_current}")

    sessions = [session for session in all_sessions if session.get("sessionId") != current_session_id]
    sessions = sorted(sessions, key=lambda session: str(session.get("createdAt", "")), reverse=True)[:limit]

    # Log the sorted results so we can verify correct ordering
    if sessions:
        most_recent = sessions[0]
        print(f"DEBUG: list_recent_sessions - MOST RECENT prior session: id={most_recent.get('sessionId', 'unknown')[:16]}... created={most_recent.get('createdAt', 'unknown')}")

    print(f"DEBUG: list_recent_sessions - returning {len(sessions)} prior sessions (excluded current: {current_session_id[:16]}...)")
    return sessions


def format_messages_for_history(messages: list[tuple[str, str]], heading: str) -> str:
    compact: list[tuple[str, str]] = []
    for role, text in messages:
        if not text:
            continue
        if compact and compact[-1] == (role, text):
            continue
        compact.append((role, text))

    lines = [heading]
    for role, text in compact[-8:]:
        label = "You" if role == "USER" else "Assistant"
        snippet = text if len(text) <= 650 else text[:647].rstrip() + "..."
        lines.append(f"- **{label}:** {snippet}")
    return "\n".join(lines)


def is_empty_recall_summary(text: str) -> bool:
    normalized = text.lower()
    empty_markers = (
        "no previous conversation",
        "no prior conversation",
        "no earlier conversation",
        "no cross-session summaries",
        "no previous conversation was found",
        "no prior conversation found",
    )
    return any(marker in normalized for marker in empty_markers)


def is_meta_recall_summary(text: str) -> bool:
    """Detect summaries that describe recall question attempts rather than actual content.

    The SummaryMemoryStrategy summarizes ALL conversations, including recall questions.
    When a user asks "What did we discuss?", that question+response gets summarized as
    "User inquired about previous session..." which pollutes subsequent recall searches.
    This function identifies and filters these meta-summaries.
    """
    normalized = text.lower()
    meta_indicators = (
        # Summaries about asking what was discussed
        "inquired about the content of discussions",
        "inquired about previous session",
        "inquired about the previous session",
        "inquired about discussions from",
        "asked about previous conversation",
        "asked about the previous conversation",
        "asked what was discussed",
        "asked about prior sessions",
        "asked about earlier conversation",
        "requested information about previous",
        "user inquired about",
        "information request:",
        # Summaries describing inability to recall
        "no prior conversation was available",
        "no earlier context was available",
        "no cross-session context",
        "assistant indicated no previous",
        "could not find previous conversation",
        "no previous session summaries",
        # Meta-conversation indicators
        "what did we discuss",
        "what was discussed earlier",
        "previous question",
        "last question",
        "remind me what we talked",
    )
    return any(marker in normalized for marker in meta_indicators)


def is_generated_history_response(text: str) -> bool:
    normalized = text.lower().strip()
    response_markers = (
        "here is what we discussed earlier in this session:",
        "here is what we discussed in a recent prior session:",
        "here is what i found from your prior sessions:",
    )
    return any(normalized.startswith(marker) for marker in response_markers)


def clean_memory_summary(text: str) -> str:
    text = re.sub(r'<topic name="([^"]+)">\s*', r'**\1:**\n', text)
    text = re.sub(r"</topic>", "", text)
    text = re.sub(r"\n\s*\*\*(?:Additional )?Tool Usage Attempts:\*\*.*?(?=\n\s*\*\*|\Z)", "\n", text, flags=re.DOTALL)
    text = re.sub(r"At timestamp \d+ \([^)]+\),?\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r"at timestamp \d+ \([^)]+\),?\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\n?The response took[^\n]*", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"Despite tool failures and irrelevant search results,\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r" at timestamp \d+ \([^)]+\)", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\n\s*\n\s*\n+", "\n\n", text)
    return text.strip()


def filter_substantive_history_messages(messages: list[tuple[str, str]]) -> list[tuple[str, str]]:
    substantive: list[tuple[str, str]] = []
    for role, text in messages:
        if role == "USER" and is_memory_history_question(text):
            continue
        if role == "ASSISTANT" and (is_empty_recall_summary(text) or is_generated_history_response(text)):
            continue
        substantive.append((role, text))
    return substantive


def build_previous_question_response(messages: list[tuple[str, str]]) -> str:
    for role, text in reversed(messages):
        if role == "USER" and text:
            return f'Your previous question was: "{text}"'
    return (
        "I do not have your previous question available for this user yet. "
        "Ask a new question and I will keep the conversation in memory for this session."
    )


def search_cross_session_summaries(actor_id: str, current_session_id: str, query: str, top_k: int = 8) -> list[str]:
    """Search for long-term memory summaries across ALL prior sessions for this actor.

    Uses namespace_path for hierarchical search (AWS recommended approach) and
    filters out meta-summaries about recall questions themselves.

    NOTE: This performs SEMANTIC search, not time-based. Use search_specific_session_summaries
    for time-scoped (most recent) session recall.
    """
    if not MEMORY_ID:
        return []

    query_manager = get_memory_query_manager(memory_id=MEMORY_ID, region=REGION)
    if query_manager is None:
        print(f"DEBUG: query_manager is None, cannot search long-term memories")
        return []

    namespace_path = f"/summaries/{actor_id}/"
    try:
        # Use search_long_term_memories with namespace_prefix for hierarchical search
        memories = query_manager.search_long_term_memories(
            query=query,
            namespace_prefix=namespace_path,
            top_k=top_k * 3,  # Fetch extra to account for filtering
        )
    except TypeError:
        # Fallback if max_results is not supported
        try:
            memories = query_manager.search_long_term_memories(
                query=query,
                namespace_prefix=namespace_path,
                top_k=top_k * 3,
            )
        except Exception as exc:
            print(f"WARNING: search_long_term_memories failed: {exc}")
            memories = []
    except Exception as exc:
        print(f"WARNING: search_long_term_memories failed: {exc}")
        memories = []

    print(f"DEBUG: search_cross_session_summaries raw_count={len(memories or [])} namespace_path={namespace_path}")

    summaries: list[str] = []
    seen = set()

    for memory in memories or []:
        # Exclude summaries from the current session
        namespaces = memory.get("namespaces") or []
        namespace = namespaces[0] if namespaces else memory.get("namespace", "")
        if f"/{current_session_id}/" in str(namespace):
            print(f"DEBUG: Skipping summary from current session")
            continue

        content = memory_content_to_text(memory)
        if not content:
            continue
        if content in seen:
            continue
        seen.add(content)

        # Filter out empty recall summaries
        if is_empty_recall_summary(content):
            print(f"DEBUG: Filtered empty recall summary: {content[:80]}...")
            continue

        # Filter out meta-summaries about recall questions themselves
        if is_meta_recall_summary(content):
            print(f"DEBUG: Filtered meta-recall summary: {content[:80]}...")
            continue

        # Clean and add the summary
        cleaned = clean_memory_summary(content)
        if cleaned:
            summaries.append(cleaned)
            if len(summaries) >= top_k:
                break

    print(f"OBSERVABILITY actor_id={mask_identifier(actor_id)} event=cross_session_summaries filtered_count={len(summaries)}")
    return summaries


def search_specific_session_summaries(actor_id: str, target_session_id: str, query: str, top_k: int = 5) -> list[str]:
    """Search for long-term memory summaries from a SPECIFIC session.

    Use this for "previous session" recall where we want ONLY the most recent session,
    not semantically similar content from older sessions.
    """
    if not MEMORY_ID or not memory_client:
        return []

    namespace = f"/summaries/{actor_id}/{target_session_id}/"
    print(f"DEBUG: search_specific_session_summaries namespace={namespace}")

    try:
        memories = memory_client.retrieve_memories(
            memory_id=MEMORY_ID,
            namespace=namespace,
            query=query,
            top_k=top_k * 2,  # Fetch extra for filtering
        )
    except Exception as exc:
        print(f"WARNING: Failed to retrieve specific session summaries: {exc}")
        return []

    summaries: list[str] = []
    seen = set()

    for memory in memories or []:
        content = memory_content_to_text(memory)
        if not content:
            continue
        if content in seen:
            continue
        seen.add(content)

        if is_empty_recall_summary(content):
            continue
        if is_meta_recall_summary(content):
            continue

        cleaned = clean_memory_summary(content)
        if cleaned:
            summaries.append(cleaned)
            if len(summaries) >= top_k:
                break

    print(f"DEBUG: search_specific_session_summaries found {len(summaries)} from session {target_session_id[:12]}...")
    return summaries


def build_history_response(actor_id: str, session_id: str, query: str) -> tuple[str, int]:
    question_recall = is_previous_question_query(query)
    normalized_query = query.lower()

    # Detect if user is asking about THE (most recent) previous session specifically
    # vs asking broadly about prior conversations
    is_single_previous_session_query = any(marker in normalized_query for marker in (
        "the previous session",
        "the last session",
        "my previous session",
        "my last session",
        "previous session?",
        "last session?",
    ))

    print(f"DEBUG: build_history_response - actor={mask_identifier(actor_id)} session={session_id[:16]}...")
    print(f"DEBUG: build_history_response - is_single_previous_session_query={is_single_previous_session_query} question_recall={question_recall}")
    print(f"DEBUG: build_history_response - query='{query[:80]}...'")

    # Step 1: Check current session messages (same-session recall)
    current_messages = filter_substantive_history_messages([
        message for message in get_session_messages(actor_id, session_id)
        if clean_history_text(message[1]).lower() != clean_history_text(query).lower()
    ])
    print(f"DEBUG: Step 1 - current_messages count: {len(current_messages)}")
    if current_messages:
        if question_recall:
            return build_previous_question_response(current_messages), 0
        return format_messages_for_history(current_messages, "Here is what we discussed earlier in this session:"), 0

    # Step 2: Get list of prior sessions sorted by recency
    recent_sessions = list_recent_sessions(actor_id, session_id, limit=5)
    print(f"DEBUG: Step 2 - recent_sessions count: {len(recent_sessions)}")

    # Step 3: If asking about THE previous session, only search that specific session
    if is_single_previous_session_query and recent_sessions:
        most_recent_session = recent_sessions[0]
        most_recent_session_id = most_recent_session.get("sessionId")
        print(f"DEBUG: Step 3 - searching ONLY most recent session: {most_recent_session_id[:16] if most_recent_session_id else 'None'}...")
        print(f"DEBUG: User asked about THE previous session, targeting session {most_recent_session_id[:12] if most_recent_session_id else 'unknown'}...")

        if most_recent_session_id:
            # First try long-term summaries from ONLY the most recent session
            summaries = search_specific_session_summaries(actor_id, most_recent_session_id, query)
            if summaries:
                lines = ["Here is what we discussed in the previous session:"]
                for summary in summaries:
                    lines.append(f"- {summary}")
                return "\n".join(lines), len(summaries)

            # Fall back to short-term events if summaries not ready
            previous_messages = get_session_messages(actor_id, most_recent_session_id, limit=30)
            previous_messages = filter_substantive_history_messages(previous_messages)

            if previous_messages:
                if question_recall:
                    return build_previous_question_response(previous_messages), 0
                return format_messages_for_history(previous_messages, "Here is what we discussed in the previous session:"), 0

        # No content found in the most recent session
        print(f"DEBUG: Step 3 - no content found in most recent session, returning 'still processing' message")
        return (
            "I found your previous session but no conversation content is available yet. "
            "Long-term memory extraction may still be processing. Please wait a moment and try again.",
            0,
        )

    # If is_single_previous_session_query but no recent_sessions, we skip to Step 4/5
    if is_single_previous_session_query:
        print(f"DEBUG: Step 3 SKIPPED - is_single_previous_session_query=True but recent_sessions is empty")
    else:
        print(f"DEBUG: Step 3 SKIPPED - is_single_previous_session_query=False (broad prior sessions query)")

    # Step 4: For broader queries (not specifically about THE previous session),
    # use hierarchical semantic search across ALL prior sessions
    print(f"DEBUG: Step 4 - starting semantic search across all prior sessions")
    cross_session_summaries = search_cross_session_summaries(actor_id, session_id, query)
    print(f"DEBUG: Step 4 - semantic search returned {len(cross_session_summaries)} summaries")
    if cross_session_summaries:
        lines = ["Here is what I found from your prior sessions:"]
        for summary in cross_session_summaries:
            lines.append(f"- {summary}")
        return "\n".join(lines), len(cross_session_summaries)

    # Step 5: If no long-term summaries found, check short-term events from prior sessions
    # (useful when summary extraction hasn't completed yet)
    print(f"DEBUG: Step 5 - checking short-term events from {len(recent_sessions)} prior sessions")
    for i, session in enumerate(recent_sessions):
        previous_session_id = session.get("sessionId")
        if not previous_session_id:
            continue

        previous_messages = get_session_messages(actor_id, previous_session_id, limit=30)
        previous_messages = filter_substantive_history_messages(previous_messages)
        print(f"DEBUG: Step 5 - session[{i}] {previous_session_id[:16]}... has {len(previous_messages)} messages")

        if previous_messages and question_recall:
            print(f"DEBUG: Step 5 - returning previous_question_response from session[{i}]")
            return build_previous_question_response(previous_messages), 0

        if previous_messages:
            print(f"DEBUG: Step 5 - returning messages from session[{i}] with 'a recent prior session' heading")
            return format_messages_for_history(previous_messages, "Here is what we discussed in a recent prior session:"), 0

    print(f"DEBUG: No prior conversation found - returning default message")
    return (
        "I do not have earlier conversation context available for this user yet. "
        "Ask a new question and I will keep the conversation in memory for this session.",
        0,
    )


def clean_response(text: str) -> str:
    # Remove paired XML-style tags (thinking, reasoning, etc.)
    text = re.sub(r"<thinking>.*?</thinking>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<reasoning>.*?</reasoning>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<reflection>.*?</reflection>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<[^>]+>.*?</[^>]+>", "", text, flags=re.DOTALL)
    # Remove orphaned opening tags (e.g., "<thinking>\n..." without a closing tag)
    text = re.sub(r"<(thinking|reasoning|reflection|analysis|step)[^>]*>\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\n\s*\n\s*\n+", "\n\n", text)
    return text.strip()


def extract_markdown_sources(text: str) -> tuple[str, list[dict]]:
    source_pattern = re.compile(r"^\s*[-*]\s*\[([^\]]+)\]\((https?://[^)\s]+)\)\s*$")
    lines = text.splitlines()
    extracted: list[dict] = []
    remove_indexes: set[int] = set()

    for index, line in enumerate(lines):
        match = source_pattern.match(line)
        if not match:
            continue
        extracted.append({"title": match.group(1).strip() or "Untitled", "url": match.group(2).strip(), "project": ""})
        remove_indexes.add(index)
        if index > 0 and re.match(r"^\s*(sources?|references?)\s*:?\s*$", lines[index - 1], re.IGNORECASE):
            remove_indexes.add(index - 1)

    if not extracted:
        return text, []

    cleaned_lines = [line for index, line in enumerate(lines) if index not in remove_indexes]
    return clean_response("\n".join(cleaned_lines)), extracted


def _call_search_fallback(query: str, top_k: int = 10) -> str:
    """Internal helper to call search_tool as a fallback. Does not catch errors."""
    payload = {"query": query, "top_k": top_k}
    extra = mcp.get_extra(HOSTED_MCP_TOOLS["search"])
    if isinstance(extra, dict):
        payload.update(extra)
    raw_result = mcp.call_tool(HOSTED_MCP_TOOLS["search"], payload)
    normalized = normalize_result(raw_result)
    record_tool_payload(normalized)
    return json.dumps(normalized, ensure_ascii=False)


@tool
def answer_tool(query: str) -> str:
    """Use for direct factual or concise how-to questions grounded in indexed content."""
    payload = {"query": query}
    extra = mcp.get_extra(HOSTED_MCP_TOOLS["answer"])
    if isinstance(extra, dict):
        payload.update(extra)
    try:
        raw_result = mcp.call_tool(HOSTED_MCP_TOOLS["answer"], payload)
    except MCPToolError as exc:
        print(f"WARNING: answer_tool failed ({exc}), falling back to search_tool")
        return _call_search_fallback(query)
    normalized = normalize_result(raw_result)
    record_tool_payload(normalized)
    return json.dumps(normalized, ensure_ascii=False)


@tool
def passage_tool(query: str, top_k: int = 8) -> str:
    """Use for detailed explanations, comparisons, and multi-step questions."""
    payload = {"query": query, "top_k": top_k}
    extra = mcp.get_extra(HOSTED_MCP_TOOLS["passage"])
    if isinstance(extra, dict):
        payload.update(extra)
    try:
        raw_result = mcp.call_tool(HOSTED_MCP_TOOLS["passage"], payload)
    except MCPToolError as exc:
        print(f"WARNING: passage_tool failed ({exc}), falling back to search_tool")
        return _call_search_fallback(query, top_k)
    normalized = normalize_result(raw_result)
    record_tool_payload(normalized)
    return json.dumps(normalized, ensure_ascii=False)


@tool
def search_tool(query: str, top_k: int = 10) -> str:
    """Use for broad exploration when the query is open-ended or underspecified."""
    payload = {"query": query, "top_k": top_k}
    extra = mcp.get_extra(HOSTED_MCP_TOOLS["search"])
    if isinstance(extra, dict):
        payload.update(extra)
    raw_result = mcp.call_tool(HOSTED_MCP_TOOLS["search"], payload)
    normalized = normalize_result(raw_result)
    record_tool_payload(normalized)
    return json.dumps(normalized, ensure_ascii=False)


@tool
def fetch_tool(item_id: str) -> str:
    """Use for fetching a specific known item by unique identifier."""
    payload = {"item_id": item_id}
    extra = mcp.get_extra(HOSTED_MCP_TOOLS["fetch"])
    if isinstance(extra, dict):
        payload.update(extra)
    try:
        raw_result = mcp.call_tool(HOSTED_MCP_TOOLS["fetch"], payload)
    except MCPToolError as exc:
        print(f"WARNING: fetch_tool failed ({exc})")
        return json.dumps({"error": str(exc), "text": f"Could not fetch item '{item_id}'. The document may not exist or the identifier may be incorrect."}, ensure_ascii=False)
    normalized = normalize_document_result(raw_result)
    record_tool_payload(normalized)
    return json.dumps(normalized, ensure_ascii=False)


def mask_identifier(value: str) -> str:
    if not value:
        return "missing"
    if len(value) <= 8:
        return f"{value[:2]}***"
    return f"{value[:4]}...{value[-4:]}"


def get_stable_actor_id(payload: dict, context: BedrockAgentCoreContext) -> str:
    if payload.get("actor_id"):
        return payload["actor_id"]

    try:
        if hasattr(context, "identity") and context.identity:
            identity = context.identity
            for attr in ("sub", "cognito_username", "username"):
                value = getattr(identity, attr, None)
                if value:
                    return value
    except Exception as exc:
        print(f"WARNING: Failed to extract identity from context: {exc}")

    if payload.get("user_id"):
        return payload["user_id"]

    raise ValueError("Authenticated user identity is required for memory-enabled chat.")


def list_previous_session_summaries(actor_id: str, session_id: str, limit: int = 5) -> list[str]:
    if not MEMORY_ID:
        return []

    query_manager = get_memory_query_manager(memory_id=MEMORY_ID, region=REGION)
    if query_manager is None:
        return []

    namespace_prefix = f"/summaries/{actor_id}/"
    try:
        records = query_manager.list_long_term_memory_records(
            namespace_prefix=namespace_prefix,
            max_results=max(limit * 5, 20),
        )
    except TypeError:
        records = query_manager.list_long_term_memory_records(namespace_prefix=namespace_prefix)
    except Exception as exc:
        print(f"WARNING: Failed to list summary memories from {namespace_prefix}: {exc}")
        return []

    summaries: list[str] = []
    seen = set()
    for record in records or []:
        if not isinstance(record, dict):
            continue

        namespaces = record.get("namespaces") or []
        namespace = namespaces[0] if namespaces else record.get("namespace", "")
        if f"/{session_id}/" in str(namespace):
            continue

        content = memory_content_to_text(record)
        if content and content not in seen:
            seen.add(content)
            summaries.append(content)

        if len(summaries) >= limit:
            break

    print(
        f"OBSERVABILITY actor_id={mask_identifier(actor_id)} event=previous_session_summaries "
        f"count={len(summaries)} namespace_prefix={namespace_prefix}"
    )
    return summaries


def search_long_term_memories(namespace_prefix: str, query: str, top_k: int = 5) -> list[dict]:
    if not MEMORY_ID or not query.strip():
        return []

    query_manager = get_memory_query_manager(memory_id=MEMORY_ID, region=REGION)
    if query_manager is None:
        return []

    try:
        memories = query_manager.search_long_term_memories(
            query=query,
            namespace_prefix=namespace_prefix,
            top_k=top_k,
            max_results=top_k,
        )
    except TypeError:
        memories = query_manager.search_long_term_memories(
            query=query,
            namespace_prefix=namespace_prefix,
            top_k=top_k,
        )
    except Exception as exc:
        print(f"WARNING: Failed to search long-term memories in {namespace_prefix}: {exc}")
        return []

    print(f"OBSERVABILITY event=long_term_search namespace_prefix={namespace_prefix} count={len(memories or [])}")
    return memories or []


def retrieve_long_term_context(actor_id: str, session_id: str, query: str) -> tuple[str, int]:
    if not MEMORY_ID or not query.strip():
        return "", 0

    context_lines: list[str] = []
    seen = set()

    # For explicit recall questions, use the deterministic session-history path.
    # It can query exact prior session namespaces and fall back to prior session
    # events immediately after session close, without waiting on parent-prefix
    # long-term summary search to succeed.
    if is_memory_history_question(query):
        history_text, history_count = build_history_response(actor_id, session_id, query)
        if history_text and not history_text.startswith("I do not have earlier conversation context available"):
            return "\n\n<user_context>\n## Cross-Session Memory\n" + history_text + "\n</user_context>", max(history_count, 1)

    for namespace_prefix in (f"/users/{actor_id}/facts/", f"/summaries/{actor_id}/"):
        memories = search_long_term_memories(namespace_prefix, query)
        for memory in memories:
            content = memory_content_to_text(memory)
            if content and content not in seen:
                seen.add(content)
                context_lines.append(f"- {content}")
            if len(context_lines) >= 5:
                break

        if len(context_lines) >= 5:
            break

    if not context_lines:
        return "", 0

    return "\n\n<user_context>\n## Cross-Session Memory\n" + "\n".join(context_lines) + "\n</user_context>", len(context_lines)


def write_fallback_memory_event(actor_id: str, session_id: str, user_text: str, assistant_text: str) -> None:
    if not memory_client or not MEMORY_ID:
        return

    try:
        memory_client.create_event(
            memory_id=MEMORY_ID,
            actor_id=actor_id,
            session_id=session_id,
            messages=[
                (user_text, "USER"),
                (assistant_text, "ASSISTANT"),
            ],
        )
    except Exception as exc:
        print(f"WARNING: Failed to store fallback memory event: {exc}")


def build_direct_history_result(actor_id: str, session_id: str, query: str) -> tuple[dict, int]:
    history_text, history_count = build_history_response(actor_id, session_id, query)
    print(
        f"OBSERVABILITY session_id={session_id} actor_id={mask_identifier(actor_id)} "
        f"event=history_intercept matches={max(history_count, 0)}"
    )

    write_fallback_memory_event(actor_id, session_id, query, history_text)

    return {
        "response": history_text,
        "session_id": session_id,
        "sources": [],
        "memory_enabled": bool(MEMORY_ID),
        "actor_id_present": True,
        "retrieved_memory_count": history_count,
    }, history_count


@app.entrypoint
def invoke(payload: dict, context: BedrockAgentCoreContext):
    controls = payload.get("controls") or {}
    mcp.set_controls(controls)

    session_id = payload.get("session_id", "default_session")
    user_text = payload.get("text") or payload.get("prompt") or ""
    end_session = payload.get("end_session", False)
    try:
        actor_id = get_stable_actor_id(payload, context)
    except ValueError as exc:
        print(f"ERROR: {exc}")
        return {
            "response": str(exc),
            "session_id": session_id,
            "sources": [],
            "memory_enabled": bool(MEMORY_ID),
            "actor_id_present": False,
            "error": "missing_actor_id",
        }

    print(f"OBSERVABILITY session_id={session_id} actor_id={mask_identifier(actor_id)} event=session_start end_session={end_session}")
    print(f"OBSERVABILITY session_id={session_id} event=request_received text_length={len(user_text)}")

    mcp.set_session_id(session_id)
    session_manager = get_memory_session_manager(
        memory_id=MEMORY_ID,
        region=REGION,
        session_id=session_id,
        actor_id=actor_id,
    )

    if end_session:
        print(f"OBSERVABILITY session_id={session_id} actor_id={mask_identifier(actor_id)} event=session_end_requested")
        # Close the session_manager to flush buffered events and trigger
        # the SummaryMemoryStrategy summarization on session close.
        # The AgentCore framework also handles end_session at the protocol
        # level, but explicit close ensures our session_manager state is
        # flushed before we return.
        if session_manager is not None:
            try:
                session_manager.close()
                print(f"OBSERVABILITY session_id={session_id} event=session_end_complete via_session_manager=true")
            except Exception as exc:
                print(f"WARNING: Failed to close session_manager on end_session: {exc}")
        elif memory_client and MEMORY_ID:
            try:
                memory_client.create_event(
                    memory_id=MEMORY_ID,
                    actor_id=actor_id,
                    session_id=session_id,
                    messages=[("Session ended by user", "SYSTEM")],
                    metadata={"type": "session_end"},
                )
                print(f"OBSERVABILITY session_id={session_id} event=session_end_complete via_fallback=true")
            except Exception as exc:
                print(f"WARNING: Failed to write session_end event: {exc}")
        return {
            "response": "Session ended successfully. Your conversation has been saved.",
            "session_id": session_id,
            "sources": [],
            "session_ended": True,
            "memory_enabled": bool(MEMORY_ID),
            "actor_id_present": True,
        }

    if is_memory_history_question(user_text):
        direct_result, history_count = build_direct_history_result(actor_id, session_id, user_text)
        if session_manager is not None:
            try:
                session_manager.close()
            except Exception as exc:
                print(f"WARNING: Failed to close session_manager after history intercept: {exc}")
        print(
            f"OBSERVABILITY session_id={session_id} event=session_complete "
            f"sources_count=0 tools_used=none retrieved_memory_count={history_count}"
        )
        return direct_result

    # Always retrieve cross-session context manually.
    # The SDK's session_manager only retrieves within the CURRENT session namespace.
    # For cross-session recall, we must query the parent /summaries/{actorId}/ path.
    conversation_context, retrieved_memory_count = retrieve_long_term_context(actor_id, session_id, user_text)
    if retrieved_memory_count:
        print(f"DEBUG: Retrieved {retrieved_memory_count} memory records for actor {mask_identifier(actor_id)}")

    print(f"OBSERVABILITY session_id={session_id} event=tool_plan_start text='{user_text[:120]}'")
    tool_payload_token = TOOL_PAYLOADS.set([])
    with TOOL_PAYLOADS_LOCK:
        TOOL_PAYLOADS_BY_SESSION[session_id] = []

    agent_kwargs = {
        "model": MODEL_ID,
        "system_prompt": SYSTEM_PROMPT + conversation_context,
        "tools": [answer_tool, passage_tool, search_tool, fetch_tool],
    }
    if session_manager is not None:
        agent_kwargs["session_manager"] = session_manager

    agent = Agent(**agent_kwargs)
    try:
        result = agent(user_text)
    finally:
        captured_tool_payloads = TOOL_PAYLOADS.get()
        with TOOL_PAYLOADS_LOCK:
            captured_tool_payloads = [*captured_tool_payloads, *TOOL_PAYLOADS_BY_SESSION.pop(session_id, [])]
        TOOL_PAYLOADS.reset(tool_payload_token)
        # Flush any buffered messages to AgentCore Memory so they are
        # available for the next invocation's session restore.
        if session_manager is not None:
            try:
                session_manager.close()
            except Exception as exc:
                print(f"WARNING: Failed to close session_manager: {exc}")

    print(f"OBSERVABILITY session_id={session_id} event=tool_plan_done")

    content = result.message.get("content", [{}])
    text = content[0].get("text") if content and isinstance(content, list) else str(result)
    text = clean_response(text)
    text, markdown_sources = extract_markdown_sources(text)

    sources: list[dict] = []
    tools_used: list[str] = []
    try:
        if hasattr(result, "tool_calls") and result.tool_calls:
            tools_used = [tool_call.name if hasattr(tool_call, "name") else str(tool_call) for tool_call in result.tool_calls]
            print(f"OBSERVABILITY session_id={session_id} event=tools_selected tools={','.join(tools_used)}")

            for tool_call in result.tool_calls:
                tool_result = getattr(tool_call, "result", None)
                if not isinstance(tool_result, str):
                    continue
                try:
                    tool_data = json.loads(tool_result)
                except json.JSONDecodeError:
                    print(f"WARNING: Failed to parse tool result as JSON for {getattr(tool_call, 'name', 'unknown')}")
                    continue
                sources.extend(build_sources_from_payload(tool_data))
        else:
            print(f"WARNING: No tool_calls found in result. Result type: {type(result)}")
    except Exception as exc:
        print(f"ERROR: Failed to extract sources: {exc}")

    if not sources and captured_tool_payloads:
        for tool_data in captured_tool_payloads:
            sources.extend(build_sources_from_payload(tool_data))
        print(f"OBSERVABILITY session_id={session_id} event=sources_extracted_from_payloads count={len(sources)}")

    if not sources and markdown_sources:
        sources.extend(markdown_sources)
        print(f"OBSERVABILITY session_id={session_id} event=sources_extracted_from_markdown count={len(sources)}")

    if not sources:
        sources.extend(retrieve_fallback_sources(user_text))

    if session_manager is None:
        write_fallback_memory_event(actor_id, session_id, user_text, text)

    print(
        f"OBSERVABILITY session_id={session_id} event=session_complete "
        f"sources_count={len(sources)} tools_used={','.join(tools_used) if tools_used else 'none'}"
    )

    valid_sources = []
    seen_source_urls = set()
    for source in sources:
        url = source.get("url", "")
        if url.startswith("http") and url not in seen_source_urls:
            seen_source_urls.add(url)
            valid_sources.append(source)

    if len(valid_sources) < len(sources):
        print(f"WARNING: Filtered {len(sources) - len(valid_sources)} sources with invalid URLs")

    return {
        "response": text,
        "session_id": session_id,
        "sources": valid_sources,
        "memory_enabled": bool(MEMORY_ID),
        "actor_id_present": True,
        "retrieved_memory_count": retrieved_memory_count,
    }


if __name__ == "__main__":
    app.run()
