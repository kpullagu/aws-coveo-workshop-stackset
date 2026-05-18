# Code References

This page summarizes the files that matter for the live workshop architecture.

## Main Repository

```text
aws-coveo-workshop-stackset/
├── .github/workflows/
│   └── deploy.yml                         # GitHub Actions – MkDocs publish to GitHub Pages
├── cfn/stacksets/
│   ├── stackset-1-prerequisites.yml       # S3, ECR cross-account replication
│   ├── stackset-2-core.yml                # Cognito, API Gateway, all Lambda functions
│   ├── stackset-2-core-part1.yml          # Cognito User Pool only (run first in new accounts)
│   ├── stackset-3-ai-services.yml         # AgentCore Runtime + Memory (uses image digest)
│   └── stackset-4-ui.yml                  # ECS Fargate service for workshop UI
├── coveo-agent/
│   ├── app.py                             # AgentCore container entry point; memory + MCP tool logic
│   ├── mcp_adapter.py                     # Translates Hosted MCP tool results for AgentCore
│   ├── memory/
│   │   ├── __init__.py
│   │   └── session.py                     # AgentCore Strands memory session manager
│   ├── Dockerfile
│   └── requirements.txt
├── frontend/
│   ├── server.js                          # Express BFF: /api/search, /api/passages,
│   │                                      #   /api/answer, /api/chat, /api/QuerySuggest,
│   │                                      #   /api/html, /api/config, /api/health
│   ├── Dockerfile
│   ├── package.json
│   └── client/
│       ├── index.html                     # Vite entry point
│       ├── vite.config.js
│       ├── package.json
│       └── src/
│           ├── App.jsx                    # Root component; backend mode state; session IDs
│           ├── index.jsx
│           ├── index.css
│           ├── components/
│           │   ├── SearchHeader.jsx       # Header; backend selector; hidden in Search Agent mode
│           │   ├── SearchResults.jsx      # Lab 1 results: search hits, answer, passages, facets
│           │   ├── SearchAgentWorkspace.jsx  # Lab 3: hero card with search + answer + follow-ups
│           │   ├── ChatBot.jsx            # Lab 2: floating chat panel (AgentCore / MCP mode)
│           │   ├── Sidebar.jsx            # Facet navigation
│           │   ├── AuthProvider.jsx       # Cognito auth context
│           │   ├── LoginButton.jsx
│           │   └── QuickViewModal.jsx
│           ├── hooks/
│           │   └── useCoveoSearchAgent.js # Headless engine + SearchBox + GeneratedAnswer controllers
│           └── services/
│               └── api.js                # Typed fetch helpers for all BFF endpoints
├── lambdas/
│   ├── agentcore_runtime_py/             # Invokes AgentCore Runtime; extracts Cognito sub as actor_id
│   ├── search_proxy/                     # Coveo Search API proxy (Lab 1)
│   ├── passages_proxy/                   # Coveo Passages API proxy (Lab 1)
│   ├── answering_proxy/                  # Coveo Answer API proxy (Lab 1)
│   ├── query_suggest_proxy/              # Coveo QuerySuggest API proxy (autocomplete)
│   ├── html_proxy/                       # Coveo HTML endpoint proxy (quick view)
│   ├── coveo_passage_tool_py/            # Coveo passage retrieval as a Bedrock Agent tool (retired)
│   └── bedrock_agent_chat/               # Bedrock Agent chat proxy (retired, not used in workshop)
├── scripts/stacksets/
│   ├── config.sh                         # Central config (prefix, account IDs, regions)
│   ├── 01-setup-master-ecr.sh            # Create ECR repos in master account
│   ├── 02b-build-push-agent-image.sh     # Build + push coveo-agent Docker image
│   ├── 03-build-push-ui-image.sh         # Build + push frontend Docker image
│   ├── 04-create-shared-lambda-layer.sh  # Package Python dependencies layer
│   ├── 05-package-lambdas.sh             # Zip all Lambda functions and upload to S3
│   ├── 07-seed-ssm-parameters.sh         # Write Coveo + MCP config to SSM in child accounts
│   ├── 10-deploy-layer1-prerequisites.sh
│   ├── 11-deploy-layer2-core.sh
│   ├── 12-deploy-layer3-ai-services.sh
│   ├── 12b-seed-agent-ssm-parameters.sh  # Seed AgentCore-specific SSM parameters
│   ├── 13-deploy-layer4-ui.sh
│   ├── 14-post-deployment-config.sh
│   └── deploy-all-stacksets.sh           # Orchestrate full deployment
└── mkdocs-workshop/
    ├── mkdocs.yml
    ├── docs/
    │   ├── index.md
    │   ├── lab1/                         # Coveo Direct APIs
    │   ├── lab2/                         # AgentCore + Hosted MCP Chatbot
    │   ├── lab3/                         # Native Coveo Search Agent
    │   └── resources/
    └── retired/                          # Old lab content (not in nav)
```

## Lab 1: Direct APIs

Request flow:

```text
Workshop UI  →  Express BFF (server.js)  →  API Gateway  →  Coveo proxy Lambdas  →  Coveo APIs
```

BFF endpoints used in Lab 1:

| Endpoint | Lambda | Purpose |
|---|---|---|
| `POST /api/search` | `search_proxy` | Full-text search with facets |
| `POST /api/passages` | `passages_proxy` | Semantic passage retrieval |
| `POST /api/answer` | `answering_proxy` | AI-generated answer |
| `POST /api/QuerySuggest` | `query_suggest_proxy` | Autocomplete suggestions |
| `POST /api/html` | `html_proxy` | Quick-view HTML content |

Primary source files:

- `frontend/server.js`
- `frontend/client/src/App.jsx`
- `frontend/client/src/components/SearchResults.jsx`
- `frontend/client/src/components/SearchHeader.jsx`
- `frontend/client/src/components/Sidebar.jsx`
- `lambdas/search_proxy/lambda_function.py`
- `lambdas/passages_proxy/lambda_function.py`
- `lambdas/answering_proxy/lambda_function.py`
- `lambdas/query_suggest_proxy/lambda_function.py`
- `lambdas/html_proxy/lambda_function.py`

## Lab 2: AgentCore + Hosted MCP Chatbot

Request flow:

```text
Workshop UI ChatBot  →  Express BFF POST /api/chat  →  API Gateway
  →  agentcore_runtime_py Lambda  →  AgentCore Runtime (coveo-agent container)
  →  Coveo Hosted MCP  →  Coveo APIs
```

AgentCore Runtime container also reads/writes AgentCore Memory on every turn.

Primary source files:

- `frontend/client/src/components/ChatBot.jsx` — floating chat UI; persists `coveo_mcp_session_id`
- `frontend/client/src/services/api.js` — `chatAPI()` call with `sessionId`, `actorId`, `endSession`
- `frontend/server.js` — `POST /api/chat` route; verifies Cognito JWT; forwards to Lambda
- `lambdas/agentcore_runtime_py/lambda_function.py` — extracts Cognito `sub` as `actor_id`; invokes AgentCore Runtime
- `coveo-agent/app.py` — agent main loop; memory recall routing; `build_history_response()`
- `coveo-agent/memory/session.py` — AgentCore Strands memory session manager
- `coveo-agent/mcp_adapter.py` — translates Hosted MCP tool results for agent use

Memory behavior:

| Concept | Source | Note |
|---|---|---|
| `actor_id` | Cognito JWT `sub` | Stable identity across sessions; extracted by Lambda |
| `session_id` | UI `localStorage` UUID | Persists through browser refresh in `coveo_mcp_session_id` |
| Short-term events | AgentCore Memory | Same-session recall; available immediately |
| Long-term summaries | AgentCore Memory strategies | Cross-session recall; extracted after `End Chat` or inactivity timeout |
| Cross-session recall | `app.py build_history_response()` | Fetches up to 50 prior sessions, sorts by date, searches most recent namespace |

## Lab 3: Native Coveo Search Agent

Request flow:

```text
Workshop UI  →  Coveo Headless (browser)  →  Coveo Search Agent  →  Coveo Index
```

No API Gateway, Lambda, or AgentCore is involved in the answer or follow-up path.

Primary source files:

- `frontend/client/src/hooks/useCoveoSearchAgent.js` — initializes `buildSearchEngine`, `buildSearchBox`, and `buildGeneratedAnswer(engine, { agentId })`; exposes `submitQuery`, `askFollowUp`, `logCitationClick`, `likeAnswer`, `dislikeAnswer`
- `frontend/client/src/components/SearchAgentWorkspace.jsx` — single hero card: search input → answer → follow-up input; header search bar is hidden when this mode is active
- `frontend/client/src/components/SearchHeader.jsx` — hides the header search container when `backendMode === 'coveoSearchAgent'`
- `frontend/client/src/App.jsx` — sets `backendMode` state; renders `SearchAgentWorkspace` instead of `SearchResults` for this mode

Headless controllers built in `useCoveoSearchAgent.js`:

| Controller | Purpose |
|---|---|
| `buildSearchEngine` | Core engine; reads config from `/api/config` (org ID, API key, pipeline, search hub) |
| `buildSearchBox` | Drives the search input; calls `searchBox.submit()` on Ask |
| `buildGeneratedAnswer(engine, { agentId })` | Streams the answer; exposes `askFollowUp()`, `like()`, `dislike()`, `logCitationClick()`, `logCopyToClipboard()` |

Configuration resolved at runtime via `GET /api/config` → `coveo.searchAgentId`, `coveo.orgId`, `coveo.searchApiKey`, `coveo.searchHub`, `coveo.searchPipeline`.

## Retired Material

Older workshop material is preserved under:

```text
mkdocs-workshop/retired/
```

Those files are not part of the live navigation.
