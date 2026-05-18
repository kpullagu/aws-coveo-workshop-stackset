import os
from typing import Optional


def _load_strands_memory_classes():
    try:
        from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig, RetrievalConfig
        from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager

        return AgentCoreMemoryConfig, RetrievalConfig, AgentCoreMemorySessionManager
    except Exception as exc:
        print(f"WARNING: AgentCore Strands memory integration unavailable: {exc}")
        return None, None, None


def _load_memory_session_manager_class():
    try:
        from bedrock_agentcore.memory.session import MemorySessionManager

        return MemorySessionManager
    except Exception as exc:
        print(f"WARNING: AgentCore MemorySessionManager unavailable: {exc}")
        return None


def get_memory_session_manager(
    *,
    memory_id: Optional[str],
    region: str,
    session_id: str,
    actor_id: str,
):
    """Return the official AgentCore Strands session manager when available.

    AgentCore uses short-term memory scoped by actor_id + session_id and
    long-term memory records under strategy-defined namespaces.

    The retrieval config uses the actor-level summaries namespace (without
    pinning to a specific sessionId) so the agent can recall context from
    *all* previous sessions for this actor, not just the current one.
    """
    if not memory_id:
        return None

    AgentCoreMemoryConfig, RetrievalConfig, AgentCoreMemorySessionManager = _load_strands_memory_classes()
    if not AgentCoreMemoryConfig or not RetrievalConfig or not AgentCoreMemorySessionManager:
        return None

    # Retrieve summaries across ALL sessions for this actor.
    # The SummaryMemoryStrategy writes to /summaries/{actorId}/{sessionId}/
    # so querying the parent path /summaries/{actorId}/ finds all session summaries.
    # The SemanticMemoryStrategy writes to /facts/{actorId}/
    # for durable cross-session factual knowledge.
    retrieval_config = {
        f"/summaries/{actor_id}/": RetrievalConfig(top_k=5, relevance_score=0.3),
        f"/users/{actor_id}/facts/": RetrievalConfig(top_k=5, relevance_score=0.3),
    }

    return AgentCoreMemorySessionManager(
        AgentCoreMemoryConfig(
            memory_id=memory_id,
            session_id=session_id,
            actor_id=actor_id,
            retrieval_config=retrieval_config,
        ),
        region or os.environ.get("AWS_REGION", "us-east-1"),
    )


def get_memory_query_manager(*, memory_id: Optional[str], region: str):
    """Return the plain MemorySessionManager used by AWS samples for LTM queries.

    AWS samples use MemorySessionManager.search_long_term_memories() and
    list_long_term_memory_records() with namespace_prefix for cross-session
    retrieval. Keep that separate from the Strands session manager used by the
    runtime agent itself.
    """
    if not memory_id:
        return None

    MemorySessionManager = _load_memory_session_manager_class()
    if not MemorySessionManager:
        return None

    return MemorySessionManager(
        memory_id=memory_id,
        region_name=region or os.environ.get("AWS_REGION", "us-east-1"),
    )
