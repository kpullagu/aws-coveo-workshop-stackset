# Code References

This page provides an overview of the workshop code repository structure and key files.

## Repository Structure

```
aws-coveo-workshop/
├── infrastructure/           # CloudFormation templates
│   ├── app-runner.yaml      # Search UI deployment
│   ├── api-gateway.yaml     # API Gateway configuration
│   ├── lambdas.yaml         # Lambda functions
│   ├── bedrock-agent.yaml   # Bedrock Agent setup
│   └── agentcore.yaml       # AgentCore runtime
├── ui/                      # React search interface
│   ├── src/
│   │   ├── components/      # UI components
│   │   ├── services/        # API clients
│   │   └── App.tsx          # Main application
│   └── package.json
├── lambdas/                 # Lambda function code
│   ├── search-proxy/        # Coveo search proxy
│   ├── passages-proxy/      # Coveo passages proxy
│   ├── answer-proxy/        # Coveo answer proxy
│   ├── agent-chat/          # Bedrock Agent chat
│   └── passage-tool/        # Agent tool implementation
├── mcp-server/              # MCP server implementation
│   ├── src/
│   │   ├── tools/           # MCP tool definitions
│   │   └── server.ts        # MCP server
│   └── Dockerfile
└── mkdocs-workshop/         # This documentation
    └── docs/
```

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

## Additional Resources

- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Bedrock Agent Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html)
- [AgentCore Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agentcore.html)
- [Coveo API Documentation](https://docs.coveo.com/en/13/api-reference/search-api)
- [MCP Protocol Specification](https://modelcontextprotocol.io/)

---

For questions about the code, refer to inline comments or ask your instructor.
