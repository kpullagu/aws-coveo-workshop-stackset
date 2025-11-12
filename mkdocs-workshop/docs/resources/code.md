# Code References

This page provides an overview of the workshop code repositories and their structure.

## Workshop Repositories

### 1. StackSet Deployment Repository

**Repository**: [aws-coveo-workshop-stackset](https://github.com//aws-coveo-workshop-stackset)

This is the main repository for deploying the complete workshop infrastructure using AWS CloudFormation StackSets.

```
aws-coveo-workshop/
├── 📁 cfn/                                    # CloudFormation Templates
│   └── 📁 stacksets/                          # StackSet Templates
│       ├── stackset-1-prerequisites.yml       # Layer 1: S3, ECR, IAM
│       ├── stackset-2-core.yml                # Layer 2: Lambda, API Gateway
│       ├── stackset-3-ai-services.yml         # Layer 3: AgentCore Runtimes
│       └── stackset-4-ui.yml                  # Layer 4: App Runner UI
│
├── 📁 scripts/stacksets/                      # Deployment Scripts
│   ├── config.sh                              # Configuration loader
│   ├── deploy-all-stacksets.sh               # ⭐ Main deployment script
│   ├── destroy-all-stacksets-v2.sh           # Complete cleanup
│   │
│   ├── 01-setup-master-ecr.sh                # Setup master ECR
│   ├── 02-build-push-mcp-image.sh            # Build MCP Server image
│   ├── 02b-build-push-agent-image.sh         # Build Agent image
│   ├── 03-build-push-ui-image.sh             # Build UI image
│   ├── 04-create-shared-lambda-layer.sh      # Create Lambda Layer
│   ├── 05-package-lambdas.sh                 # Package Lambda functions
│   ├── 06-setup-s3-replication-v2.sh         # Setup S3 replication
│   ├── 07-seed-ssm-parameters.sh             # Seed SSM parameters
│   │
│   ├── 10-deploy-layer1-prerequisites.sh     # Deploy Layer 1
│   ├── 11-deploy-layer2-core.sh              # Deploy Layer 2
│   ├── 12-deploy-layer3-ai-services.sh       # Deploy Layer 3
│   ├── 12b-seed-agent-ssm-parameters.sh      # Seed Agent SSM params
│   ├── 13-deploy-layer4-ui.sh                # Deploy Layer 4
│   ├── 14-post-deployment-config.sh          # Post-deployment config
│   │
│   ├── enable-bedrock-model-invocation-logging.sh  # Bedrock logging
│   ├── enable-xray-cloudwatch-ingestion.sh   # X-Ray span ingestion
│   ├── test-observability.sh                 # Test observability
│   │
│   ├── force-lambda-resync.sh                # Force Lambda re-upload
│   ├── test-active-replication.sh            # Test S3 replication
│   ├── update-ecr-repo-policy.sh             # Update ECR policies
│   └── fix-lambda-layer-permissions.sh       # Fix layer permissions
│
├── 📁 coveo-agent/                            # AgentCore Agent
│   ├── app.py                                 # Main agent application
│   ├── mcp_adapter.py                         # MCP client adapter
│   ├── sigv4_transport.py                     # AWS SigV4 auth
│   ├── agent-template.yaml                    # AgentCore deployment config
│   ├── Dockerfile                             # Agent container
│   └── requirements.txt                       # Python dependencies
│
├── 📁 coveo-mcp-server/                       # MCP Server
│   ├── mcp_server.py                          # MCP server application
│   ├── coveo_api.py                           # Coveo API integration
│   ├── mcp-server-template.yaml               # CloudFormation template
│   ├── Dockerfile                             # MCP container
│   └── requirements.txt                       # Python dependencies
│
├── 📁 frontend/                               # React UI + Express BFF
│   ├── 📁 client/                             # React application
│   │   ├── 📁 src/
│   │   │   ├── 📁 components/                 # React components
│   │   │   ├── 📁 services/                   # API client
│   │   │   ├── App.js                         # Main app
│   │   │   └── index.js                       # Entry point
│   │   └── package.json                       # React dependencies
│   ├── server.js                              # Express BFF
│   ├── Dockerfile                             # Multi-stage build
│   └── package.json                           # BFF dependencies
│
├── 📁 lambdas/                                # Lambda Functions
│   ├── 📁 agentcore_runtime_py/               # AgentCore handler
│   ├── 📁 search_proxy/                       # Coveo search
│   ├── 📁 passages_proxy/                     # Coveo passages
│   ├── 📁 answering_proxy/                    # Coveo answering
│   ├── 📁 query_suggest_proxy/                # Query suggestions
│   ├── 📁 html_proxy/                         # HTML content proxy
│   ├── 📁 bedrock_agent_chat/                 # Bedrock Agent chat
│   └── 📁 coveo_passage_tool_py/              # Bedrock Agent tool
│
├── 📁 config/                                 # Configuration
│   ├── env.py                                 # Python env loader
│   └── env.schema.json                        # Environment schema
│
├── 📁 mkdocs-workshop/                        # This documentation site
│   └── docs/
│
├── .dockerignore                              # Docker ignore rules
├── .env.stacksets.example                     # Config template ✅ COMMIT
├── .env.stacksets                             # Your config ❌ GITIGNORED
├── .env.example                               # Frontend config template ✅ COMMIT
├── .env.template                              # Environment template
├── .env                                       # Frontend config ❌ GITIGNORED
├── .gitignore                                 # Git ignore rules
├── LICENSE                                    # MIT License
├── README.md                                  # Main documentation
└── SETUP_GUIDE.md                             # Setup instructions
```

### 2. Content Indexing Repository

**Repository**: [aws-coveo-workshop-index](https://github.com//aws-coveo-workshop-index)

Code to index content from public websites into Coveo platform. This repository contains web scrapers and indexers for various financial and government sources.

```
aws-coveo-workshop-index/
├── Common Libraries/                # Shared libraries used by scrapers and push scripts
│   ├── common_scraper_lib.py
│   └── common_push_lib.py
├── Field Management/                # Coveo custom field helpers and docs
│   ├── create_coveo_fields.py
│   ├── create_fields_one_by_one.py
│   ├── create_fields_instructions.md
│   └── fields_to_create.json
├── Push Scripts/                    # Helper scripts that upload batches to Coveo
│   ├── coveo_push_batch.py
│   ├── push_wikimedia.py
│   ├── push_ftc.py
│   ├── push_irs.py
│   └── ...
├── Source Indexers/                 # Scrapers for each supported source
│   ├── wikimedia_to_coveo_indexer.py
│   ├── ftc_indexer.py
│   ├── irs_indexer.py
│   └── ...
├── requirements.txt                 # Python dependencies
├── output/                          # Generated JSON batches (Git ignored)
├── ui/                              # Optional search UI prototype
└── README.md                        # This file

```

**Key Features**:

- Web scraping from 11+ authoritative sources
- Batch push to Coveo using Push API
- Custom field creation and management
- Error handling and logging
- Configurable via environment variables

### 3. Platform Snapshot Repository

**Repository**: [aws-coveo-workshop-platform-snapshot](https://github.com//aws-coveo-workshop-platform-snapshot)

Coveo Platform snapshot that can be replicated into a new Coveo organization. This snapshot contains the complete platform configuration including sources, query pipelines, ML models, fields, and security settings.

```
aws-coveo-workshop-platform-snapshot/
├── Snapshot-awsworkshopthsskpki-u52gvcsw7gbpvohlu5n3522f4i.json
└── README.md
```

**Snapshot Contents**:

The JSON snapshot file includes:

- **Sources**: 11 configured sources (CFPB, FDIC, FRB, IRS, etc.)
- **Query Pipelines**: Search logic and ranking rules
- **ML Models**: Machine learning configurations for relevance
- **Fields**: Custom field definitions and mappings
- **Security**: Access control and permissions
- **Extensions**: Custom processing extensions
- **Search Interfaces**: UI configurations

**Usage**:

This snapshot can be imported into a new Coveo organization to replicate the entire workshop environment, including all sources, configurations, and settings used in the labs.

## Key Components

### Lambda Functions

The workshop uses several Lambda functions to integrate with Coveo APIs:

#### Search Proxy (`lambdas/search_proxy/`)

- Proxies search requests to Coveo Search API
- Handles query parameters and facet configuration
- Returns formatted search results

#### Passages Proxy (`lambdas/passages_proxy/`)

- Retrieves relevant passages from Coveo
- Implements semantic search
- Provides passage ranking and source attribution

#### Answering Proxy (`lambdas/answering_proxy/`)

- Generates AI answers using Coveo Answer API
- Manages question understanding and answer generation
- Includes citation management

#### Bedrock Agent Chat (`lambdas/bedrock_agent_chat/`)

- Handles Bedrock Agent invocations
- Manages session state and memory
- Processes agent responses

#### Coveo Passage Tool (`lambdas/coveo_passage_tool_py/`)

- Bedrock Agent tool for passage retrieval
- Integrates with Coveo Passages API
- Formats results for agent consumption

#### AgentCore Runtime (`lambdas/agentcore_runtime_py/`)

- Handles AgentCore runtime invocations
- Manages MCP server communication
- Processes multi-tool orchestration

### Frontend Application

The React-based UI (`frontend/`) provides:

- Backend mode selection (Coveo, Bedrock Agent, AgentCore MCP)
- Search interface with facets
- Chat interface for conversational AI
- Real-time response rendering
- Session management

### MCP Server

The Coveo MCP Server (`coveo-mcp-server/`) implements:

- **search_coveo**: Search tool for Coveo index
- **passage_retrieval**: Passage retrieval tool
- **answer_question**: Answer generation tool
- Model Context Protocol compliance
- Tool registration and discovery

### Deployment Scripts

Key deployment scripts in `scripts/`:

- `deploy-complete-workshop.sh`: Full workshop deployment
- `deploy-main-infra.sh`: Core infrastructure only
- `deploy-agent.sh`: Bedrock Agent deployment
- `deploy-mcp.sh`: MCP server deployment
- `deploy-ui-apprunner.sh`: UI deployment
- `package-lambdas.sh`: Lambda packaging
- `destroy.sh`: Cleanup and teardown

## Key Files

### Lambda Functions

#### Search Proxy (`lambdas/search-proxy/index.js`)

Proxies search requests to Coveo Search API.

**Key Features**:

- Query parameter handling
- Facet configuration
- Result formatting
- Error handling

#### Passages Proxy (`lambdas/passages-proxy/index.js`)

Retrieves relevant passages from Coveo.

**Key Features**:

- Semantic search
- Passage ranking
- Source attribution
- Context extraction

#### Answer Proxy (`lambdas/answer-proxy/index.js`)

Generates AI answers using Coveo Answer API.

**Key Features**:

- Question understanding
- Answer generation
- Citation management
- Response formatting

#### Agent Chat (`lambdas/agent-chat/index.js`)

Handles Bedrock Agent invocations.

**Key Features**:

- Session management
- Agent invocation
- Response streaming
- Memory handling

#### Passage Tool (`lambdas/passage-tool/index.js`)

Bedrock Agent tool for passage retrieval.

**Key Features**:

- Tool schema definition
- Coveo API integration
- Result formatting
- Error handling

### MCP Server

#### MCP Server (`mcp-server/src/server.ts`)

Implements Model Context Protocol server.

**Key Features**:

- Tool registration
- Request handling
- Response formatting
- Error management

#### MCP Tools (`mcp-server/src/tools/`)

Individual tool implementations:

- `search_coveo.ts` - Search tool
- `passage_retrieval.ts` - Passages tool
- `answer_question.ts` - Answer tool

### UI Components

#### Search Interface (`ui/src/components/SearchInterface.tsx`)

Main search UI component.

**Key Features**:

- Backend selection
- Query input
- Results display
- Facet filtering

#### Chat Interface (`ui/src/components/ChatInterface.tsx`)

Chatbot UI component.

**Key Features**:

- Message history
- Backend switching
- Session management
- Response rendering

### Infrastructure

#### CloudFormation Templates

**app-runner.yaml**:

- App Runner service
- Container configuration
- Environment variables
- IAM roles

**api-gateway.yaml**:

- HTTP API
- Route configuration
- Lambda integrations
- CORS settings

**bedrock-agent.yaml**:

- Agent definition
- Tool configuration
- Memory settings
- IAM permissions

**agentcore.yaml**:

- Runtime deployment
- MCP server container
- Memory configuration
- Observability setup

## Code Navigation Guide

### To Understand Direct API Integration (Lab 1)

1. Review `lambdas/search-proxy/index.js`
2. Review `lambdas/passages-proxy/index.js`
3. Review `lambdas/answer-proxy/index.js`
4. Check `infrastructure/api-gateway.yaml`

### To Understand Bedrock Agent (Lab 2)

1. Review `lambdas/agent-chat/index.js`
2. Review `lambdas/passage-tool/index.js`
3. Check `infrastructure/bedrock-agent.yaml`
4. Review agent configuration in AWS Console

### To Understand AgentCore + MCP (Lab 3)

1. Review `mcp-server/src/server.ts`
2. Review `mcp-server/src/tools/`
3. Check `infrastructure/agentcore.yaml`
4. Review MCP protocol documentation

### To Understand UI (All Labs)

1. Review `ui/src/App.tsx`
2. Review `ui/src/components/SearchInterface.tsx`
3. Review `ui/src/components/ChatInterface.tsx`
4. Review `ui/src/services/api.ts`

## Environment Variables

### Lambda Functions

```bash
COVEO_ORG_ID=your-org-id
COVEO_API_KEY=your-api-key
COVEO_SEARCH_HUB=workshop
```

### MCP Server

```bash
COVEO_ORG_ID=your-org-id
COVEO_API_KEY=your-api-key
COVEO_SEARCH_API_URL=https://platform.cloud.coveo.com/rest/search/v2
```

### UI

```bash
REACT_APP_API_ENDPOINT=your-api-gateway-url
REACT_APP_REGION=us-east-1
```

## Deployment Scripts

### Deploy All Infrastructure

```bash
./scripts/deploy-all-stacksets.sh
```

### Deploy Individual Components

```bash
# Deploy API Gateway and Lambdas
aws cloudformation deploy --template-file infrastructure/api-gateway.yaml

# Deploy Bedrock Agent
aws cloudformation deploy --template-file infrastructure/bedrock-agent.yaml

# Deploy AgentCore
aws cloudformation deploy --template-file infrastructure/agentcore.yaml
```

## Testing

### Local Development

```bash
# Run UI locally
cd ui
npm install
npm start

# Test Lambda functions locally
cd lambdas/search-proxy
npm install
npm test
```

### Integration Testing

```bash
# Test API endpoints
curl https://your-api-gateway-url/search?q=test

# Test Bedrock Agent
aws bedrock-agent-runtime invoke-agent \
  --agent-id your-agent-id \
  --session-id test-session \
  --input-text "test query"
```

## Workshop GitHub Repositories

### Infrastructure & Deployment
- [StackSet Deployment Code](https://github.com//aws-coveo-workshop-stackset) - Complete infrastructure deployment using CloudFormation StackSets
- [Content Indexing Code](https://github.com//aws-coveo-workshop-index) - Scripts to index content from public websites into Coveo
- [Platform Snapshot](https://github.com//aws-coveo-workshop-platform-snapshot) - Coveo Platform configuration snapshot for replication

### Documentation Resources

#### Coveo Documentation

- [Coveo Platform Overview](https://docs.coveo.com/)
- [Coveo Search API Reference](https://docs.coveo.com/en/13/api-reference/search-api)
- [Coveo Passages API](https://docs.coveo.com/en/3448/)
- [Coveo Answer API](https://docs.coveo.com/en/3448/)

#### AWS Documentation

- [AWS Bedrock Agent Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html)
- [AWS Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agentcore.html)

#### Protocol Specifications

- [Model Context Protocol (MCP) Specification](https://modelcontextprotocol.io/)

---

For questions about the code, refer to inline comments or ask your instructor.
