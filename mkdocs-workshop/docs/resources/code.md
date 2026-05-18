# Code References

This page summarizes the files that matter for the live workshop architecture.

## Main Repository

```text
aws-coveo-workshop-stackset/
├── cfn/stacksets/
│   ├── stackset-1-prerequisites.yml
│   ├── stackset-2-core.yml
│   ├── stackset-3-ai-services.yml
│   └── stackset-4-ui.yml
├── coveo-agent/
│   ├── app.py
│   ├── memory/session.py
│   ├── mcp_adapter.py
│   └── requirements.txt
├── frontend/
│   ├── server.js
│   └── client/src/
│       ├── App.jsx
│       ├── components/SearchAgentWorkspace.jsx
│       ├── components/ChatBot.jsx
│       ├── components/SearchHeader.jsx
│       ├── hooks/useCoveoSearchAgent.js
│       └── services/api.js
├── lambdas/
│   ├── agentcore_runtime_py/
│   ├── search_proxy/
│   ├── passages_proxy/
│   ├── answering_proxy/
│   └── query_suggest_proxy/
└── mkdocs-workshop/
```

## Lab 1: Direct APIs

Request flow:

```text
Workshop UI -> Express BFF -> API Gateway -> Coveo proxy Lambdas -> Coveo APIs
```

Primary files:

- `frontend/server.js`
- `frontend/client/src/App.jsx`
- `frontend/client/src/components/SearchResults.jsx`
- `lambdas/search_proxy/`
- `lambdas/passages_proxy/`
- `lambdas/answering_proxy/`

## Lab 2: AgentCore + Hosted MCP Chatbot

Request flow:

```text
Workshop UI ChatBot -> Express BFF -> API Gateway -> AgentCore Lambda -> AgentCore Runtime -> Coveo Hosted MCP -> Coveo
```

Primary files:

- `frontend/client/src/components/ChatBot.jsx`
- `frontend/client/src/services/api.js`
- `frontend/server.js`
- `lambdas/agentcore_runtime_py/lambda_function.py`
- `coveo-agent/app.py`
- `coveo-agent/memory/session.py`
- `coveo-agent/mcp_adapter.py`

Memory behavior:

- `lambdas/agentcore_runtime_py/lambda_function.py` extracts the Cognito `sub` and sends it as `actor_id`.
- `frontend/client/src/App.jsx` persists `coveo_mcp_session_id` through browser refresh.
- `coveo-agent/memory/session.py` creates the AgentCore Strands memory session manager.
- `coveo-agent/app.py` uses the memory session manager and Hosted MCP tools.

## Lab 3: Native Coveo Search Agent

Request flow:

```text
Workshop UI -> Coveo Headless -> Coveo Search Agent -> Coveo Index
```

Primary files:

- `frontend/client/src/hooks/useCoveoSearchAgent.js`
- `frontend/client/src/components/SearchAgentWorkspace.jsx`
- `frontend/client/src/components/SearchHeader.jsx`
- `frontend/client/src/App.jsx`

Headless controllers:

- `buildSearchEngine`
- `buildSearchBox`
- `buildGeneratedAnswer(engine, { agentId })`

The Search Agent mode is frontend-native. It does not call `/api/chat`, AgentCore, or Lambda for generated answer follow-ups.

## Retired Material

Older workshop material is preserved under:

```text
mkdocs-workshop/retired/
```

Those files are not part of the live navigation.
