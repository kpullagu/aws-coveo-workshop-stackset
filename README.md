# AWS Coveo Workshop: AI-Powered Search with Multi-Backend Architecture

[![AWS](https://img.shields.io/badge/AWS-Serverless-orange)](https://aws.amazon.com/)
[![Coveo](https://img.shields.io/badge/Coveo-Search%20API-blue)](https://www.coveo.com/)
[![React](https://img.shields.io/badge/React-18-blue)](https://reactjs.org/)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green)](https://nodejs.org/)
[![Bedrock](https://img.shields.io/badge/AWS-Bedrock-purple)](https://aws.amazon.com/bedrock/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A builder workshop demonstrating AI-powered search and answering using Coveo's platform integrated with AWS serverless services, featuring multiple backend architectures including Bedrock AgentCore Runtime and MCP Server integration.

## 🎯 Workshop Overview

This workshop demonstrates a production-ready, scalable search and AI answering solution combining:

- **Coveo Search Platform** - Enterprise search with AI-powered relevance and answering
- **AWS Serverless Architecture** - Lambda, API Gateway, Cognito, App Runner, ECR
- **Bedrock AgentCore Runtime** - Serverless agent deployment with streaming responses
- **MCP Server Integration** - Model Context Protocol for tool orchestration
- **React Frontend** - Modern UI with Cognito authentication and real-time search
- **Multiple Backend Modes** - Three distinct architectures (Coveo, BedrockAgent, CoveoMCP)

## 🏗️ Architecture

### High-Level Architecture
```
┌──────────────────────────────────────────────────────────────────┐
│                         React UI (App Runner)                    │
│  • Cognito Authentication  • Search Interface  • Facet Filters   │
│  • Backend Mode Selector   • Real-time Results • Scrollable UI   │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Express BFF (Backend for Frontend)            │
│  • Routes API calls  • JWT validation  • Response transformation │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                         API Gateway + Lambda                     │
│  • search-proxy  • passages-proxy  • answering-proxy             │
│  • bedrock-agent-chat  • agentcore-runtime  • query-suggest      │
└─────────┬────────────────────────┬────────────────────┬──────────┘
          │                        │                    │
          ▼                        ▼                    ▼
┌─────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│ Coveo Platform  │    │ AgentCore Runtime│    │   MCP Server     │
│ • Search API    │    │ • Agent Execution│    │ • Tool Provider  │
│ • Answering API │    │ • Streaming      │    │ • Coveo Tools    │
│ • Passages API  │    │ • Memory         │    │ • HTTP Transport │
└─────────────────┘    └──────────────────┘    └──────────────────┘
```

### Backend Modes

The workshop supports three production-ready backend architectures:

1. **Coveo Mode** - Direct Coveo API integration (fast, single-turn)
2. **BedrockAgent Mode** - AgentCore Runtime with Bedrock orchestration (multi-turn, streaming)
3. **CoveoMCP Mode** - MCP Server with AgentCore Gateway (tool-based, extensible)

### MCP Server Architecture

The MCP (Model Context Protocol) Server provides a tool-based architecture for AI agents:

**Deployment Approach:**
- **Local Docker Build** - Images built locally and pushed to ECR for fast iteration
- **AgentCore Runtime** - Serverless deployment with automatic scaling
- **Tool Integration** - Coveo API tools accessible via MCP protocol

**Key Components:**
- `app.py` - Main MCP server application with tool definitions
- `coveo_tools.py` - Coveo API tool implementations (search, passages, answering)
- `Dockerfile` - Container image for AgentCore Runtime deployment
- `mcp-server-template.yaml` - CloudFormation template for AWS resources

**Benefits:**
- **Extensible** - Easy to add new tools and capabilities
- **Standardized** - Uses MCP protocol for tool communication
- **Scalable** - Serverless deployment with AgentCore Runtime
- **Fast Development** - Local Docker builds for rapid iteration

## 🚀 Quick Start

### Prerequisites

- **AWS Account** with appropriate permissions
- **AWS CLI v2** configured with credentials
- **Docker Desktop** installed and running
- **Node.js 18+** and npm
- **Bash shell** (Git Bash on Windows, native on macOS/Linux)
- **Coveo Organization** with API access

### Environment Setup

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd Workshop-Full
   ```

2. **Configure environment variables:**
   ```bash
   cp .env.example .env
   # Edit .env with your Coveo credentials
   ```

   Required variables:
   ```bash
   COVEO_ORG_ID=your-org-id
   COVEO_SEARCH_API_KEY=your-api-key
   COVEO_ANSWER_CONFIG_ID=your-answer-config-id
   ```

3. **Deploy the complete workshop:**
   ```bash
   ./deploy-complete-workshop.sh
   ```

   **Deployment time:** ~8-12 minutes

4. **Access your application:**
   - Frontend URL will be displayed after deployment
   - Test credentials: `testuser` / `TempPass123!`

## 📁 Project Structure

```
Workshop-Full/
├── 📁 cfn/                          # CloudFormation Infrastructure as Code
│   ├── master.yml                   # Main orchestration template
│   ├── shared-core.yml              # Core infrastructure (API Gateway, Lambda)
│   ├── shared-core-apprunner.yml    # App Runner specific resources
│   ├── auth-cognito.yml             # Cognito User Pool & authentication
│   ├── bedrock-agent.yml            # Bedrock Agent configuration
│   ├── agentcore-runtime.yml        # AgentCore Runtime deployment
│   └── ui-apprunner.yml             # App Runner UI deployment
│
├── 📁 frontend/                     # React UI + Express BFF
│   ├── 📁 client/                   # React application
│   │   ├── 📁 src/
│   │   │   ├── 📁 components/       # React components
│   │   │   │   ├── SearchHeader.js  # Search bar with clear button
│   │   │   │   ├── SearchResults.js # Results display
│   │   │   │   ├── Sidebar.js       # Scrollable facet filters
│   │   │   │   ├── AuthProvider.js  # Cognito auth context
│   │   │   │   ├── LoginButton.js   # Authentication UI
│   │   │   │   ├── QuickViewModal.js# Document preview
│   │   │   │   └── ChatBot.js       # Chat interface
│   │   │   ├── 📁 services/
│   │   │   │   └── api.js           # API client
│   │   │   ├── App.js               # Main app component
│   │   │   ├── index.js             # React entry point
│   │   │   └── index.css            # Global styles
│   │   ├── 📁 public/               # Static assets
│   │   └── package.json             # React dependencies
│   ├── server.js                    # Express BFF server
│   ├── package.json                 # BFF dependencies
│   ├── Dockerfile                   # Multi-stage Docker build
│   └── README.md                    # Frontend documentation
│
├── 📁 lambdas/                      # AWS Lambda Functions
│   ├── 📁 search_proxy/             # Coveo search integration
│   ├── 📁 passages_proxy/           # Coveo passages retrieval
│   ├── 📁 answering_proxy/          # Coveo answering API
│   ├── 📁 query_suggest_proxy/      # Query suggestions
│   ├── 📁 html_proxy/               # HTML content proxy
│   ├── 📁 agentcore_runtime_py/     # AgentCore runtime handler
│   ├── 📁 bedrock_agent_chat/       # Bedrock Agent integration
│   └── 📁 coveo_passage_tool_py/    # Bedrock Agent tool
│
├── 📁 coveo-agent/                  # AgentCore Agent Application
│   ├── app.py                       # Main agent application
│   ├── mcp_adapter.py               # MCP client adapter
│   ├── sigv4_transport.py           # AWS SigV4 authentication
│   ├── agent-template.yaml          # AgentCore deployment config
│   ├── requirements.txt             # Python dependencies
│   └── Dockerfile                   # Agent container image
│
├── 📁 coveo-mcp-server/             # MCP Server Application
│   ├── app.py                       # Main MCP server application
│   ├── coveo_tools.py               # Coveo API tool implementations
│   ├── mcp-server-template.yaml     # CloudFormation deployment config
│   ├── requirements.txt             # Python dependencies
│   └── Dockerfile                   # MCP server container image
│
├── 📁 scripts/                      # Deployment Scripts
│   ├── deploy-complete-workshop.sh  # ⭐ One-click complete deployment
│   ├── deploy-main-infra.sh         # Core infrastructure
│   ├── deploy-mcp.sh                # MCP server deployment
│   ├── deploy-agent.sh              # AgentCore agent deployment
│   ├── deploy-ui-apprunner.sh       # UI to App Runner
│   ├── configure-cognito.sh         # Cognito authentication setup
│   ├── validate-before-deploy.sh    # Prerequisites check
│   ├── package-lambdas.sh           # Lambda packaging
│   ├── seed-ssm-secrets.sh          # SSM parameter seeding
│   ├── show-deployment-info.sh      # Display deployment info
│   └── destroy.sh                   # Complete cleanup
│
├── 📁 config/                       # Configuration
│   ├── env.py                       # Python env loader
│   └── env.schema.json              # Environment schema
│
├── 📁 docs/                         # Documentation
│   └── [other documentation files]
│
├── 📁 archive/                      # Archived/old files
├── .env                             # Environment variables (not in git)
├── .env.example                     # Example environment file
├── .env.template                    # Environment template
├── .gitignore                       # Git ignore rules
├── .dockerignore                    # Docker ignore rules
├── LICENSE                          # MIT License
└── README.md                        # This file
```

## 🛠️ Deployment Options

### Option 1: Complete One-Click Deployment (Recommended)

```bash
# Deploy everything with one command
./deploy-complete-workshop.sh
```

**What it deploys:**
- ✅ AWS infrastructure (CloudFormation)
- ✅ Lambda functions and API Gateway
- ✅ Cognito authentication
- ✅ MCP Server (local Docker build → ECR → AgentCore Runtime)
- ✅ Agent Runtime (orchestrator for MCP tools)
- ✅ UI deployment to App Runner
- ✅ Test user creation and Cognito configuration
- ✅ Complete end-to-end setup

### Option 2: Step-by-Step Deployment

```bash
# 1. Validate prerequisites
bash scripts/validate-before-deploy.sh

# 2. Deploy complete workshop (recommended)
bash scripts/deploy-complete-workshop.sh

# OR deploy components individually:

# 2a. Deploy core infrastructure
./scripts/deploy-main-infra.sh --region us-east-1

# 2b. Deploy MCP server
./scripts/deploy-mcp.sh

# 2c. Deploy Agent runtime
./scripts/deploy-agent.sh

# 2d. Deploy UI
./scripts/deploy-ui-apprunner.sh --region us-east-1

# 2e. Configure Cognito authentication
./scripts/configure-cognito.sh --region us-east-1
```

### Option 3: Cognito Configuration Only

If you need to update Cognito settings after deployment:

```bash
# Configure Cognito callback URLs and test user
bash scripts/configure-cognito.sh

# With custom test user credentials
TEST_USER_EMAIL="myuser@example.com" TEST_USER_PASSWORD="MyPassword123!" \
bash scripts/configure-cognito.sh
```

### Option 4: Development Mode

```bash
# Deploy infrastructure only
./scripts/deploy-main-infra.sh --region us-east-1

# Run UI locally
cd frontend
npm install
npm start
```

### MCP Server Development

For MCP server development and testing:

```bash
# Deploy MCP server with local changes
./scripts/deploy-mcp.sh

# The script will:
# 1. Build Docker image locally from coveo-mcp-server/
# 2. Push to ECR repository
# 3. Deploy to AgentCore Runtime
# 4. Update CloudFormation stack

# Test MCP server deployment
./scripts/deploy-agent.sh  # Deploy agent that uses MCP server
```

## 🧪 Testing the Workshop

### 1. Authentication Test
```bash
# Test API Gateway health endpoint
curl -X GET https://your-api-gateway-url/health
```

### 2. Search API Test
```bash
# Test search across Wikipedia, FDIC, investor.gov, CFPB, CDC content
curl -X POST "https://your-api-gateway-url/api/search" \
  -H "Authorization: Bearer your-jwt-token" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "what is cryptocurrency",
    "backendMode": "coveo",
    "numberOfResults": 10
  }'
```

### 3. Answering API Test
```bash
# Test AI answering from financial and health knowledge sources
curl -X POST "https://your-api-gateway-url/api/answer" \
  -H "Authorization: Bearer your-jwt-token" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "How does FDIC insurance protect my bank deposits?",
    "backendMode": "coveo"
  }'
```

### 4. Passages API Test
```bash
# Test passage retrieval from indexed content
curl -X POST "https://your-api-gateway-url/api/passages" \
  -H "Authorization: Bearer your-jwt-token" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "travel safety tips",
    "backendMode": "coveo",
    "numberOfPassages": 5
  }'
```

### 5. Multi-turn Conversation Test
```bash
# Test Bedrock Agent with AgentCore Runtime
curl -X POST "https://your-api-gateway-url/api/chat" \
  -H "Authorization: Bearer your-jwt-token" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What are the benefits of diversifying investments?",
    "backendMode": "bedrockAgent",
    "sessionId": "test-session-123"
  }'
```

### Example Queries for Testing

**Financial Topics** (from FDIC, investor.gov, CFPB):
- "What is compound interest?"
- "How does FDIC insurance work?"
- "What are the risks of investing in stocks?"
- "How to protect against identity theft?"

**Travel Topics** (from Wikivoyage, CDC):
- "Best time to visit Paris"
- "Travel safety tips for Europe"
- "Required vaccinations for international travel"
- "How to exchange currency abroad"

**General Knowledge** (from Wikipedia, Wikibooks):
- "What is blockchain technology?"
- "History of the Federal Reserve"
- "How does encryption work?"
- "What is machine learning?"

## 📚 Content Sources

The workshop indexes and searches content from multiple authoritative sources:

**Financial & Investment Knowledge:**
- 💰 **FDIC** (Federal Deposit Insurance Corporation) - Banking and deposit insurance information
- 📈 **Investor.gov** - SEC investor education and protection resources
- 🏦 **CFPB** (Consumer Financial Protection Bureau) - Consumer finance guidance

**Travel & Health:**
- ✈️ **Wikivoyage** - Comprehensive travel guides and destination information
- 🏥 **CDC** (Centers for Disease Control) - Health and travel safety guidelines

**General Knowledge:**
- 📚 **Wikipedia** - Comprehensive encyclopedia covering all topics
- 📖 **Wikibooks** - Educational textbooks and learning materials
- 📰 **Wikinews** - Current events and news articles
- 💬 **Wikiquote** - Notable quotations and sayings

### Search Capabilities

- **Full-text search** across all indexed content sources
- **Faceted navigation** by source (project) and document type
- **AI-powered answering** with citations from authoritative sources
- **Passage retrieval** for relevant excerpts and context
- **Multi-turn conversations** for complex, follow-up queries
- **Query suggestions** for improved search experience

## 🎨 Frontend Features

### React Components

- **AuthProvider** - Cognito authentication context
- **LoginButton** - Authentication UI component
- **SearchHeader** - Search bar with centered clear button
- **SearchResults** - Results display with load more functionality
- **Sidebar** - Scrollable facet filters (Project, Document Type, etc.)
- **QuickViewModal** - Document preview modal
- **ChatBot** - Multi-turn conversation UI
- **BackendSelector** - Switch between different AI modes

### Key Features

- 🔐 **JWT Authentication** with Cognito
- � **Realo-time Search** across Wikipedia, FDIC, investor.gov, CFPB, CDC, Wikivoyage
- 📊 **Facet Filters** - Filter by project (Wikipedia, Wikivoyage, etc.) and document type
- 💬 **AI Answering** with citations from authoritative sources
- 🎯 **Multiple Backend Modes** - Coveo, BedrockAgent, CoveoMCP
- 📱 **Responsive Design** for mobile and desktop
- ⚡ **Load More** functionality for browsing large result sets
- ✨ **Quick View** modal for document preview

## 🔧 Backend Architecture

### AWS Lambda Functions

| Function | Purpose | Integration |
|----------|---------|-------------|
| `search_proxy` | Search across content sources | Coveo Search API |
| `passages_proxy` | Retrieve relevant passages | Coveo Passages API |
| `answering_proxy` | AI-powered answering | Coveo Answering API |
| `query_suggest_proxy` | Query suggestions | Coveo Query Suggest API |
| `html_proxy` | HTML content retrieval | Coveo HTML API |
| `agentcore_runtime_py` | AgentCore runtime handler | AgentCore Runtime |
| `bedrock_agent_chat` | Multi-turn conversations | Bedrock Agent |
| `coveo_passage_tool_py` | Bedrock Agent tool | Coveo API |

### API Gateway Routes

```
GET  /health                    # Health check endpoint
POST /api/search                # Search across all content sources
POST /api/passages              # Retrieve relevant passages
POST /api/answer                # AI-powered answering with citations
POST /api/chat                  # Multi-turn conversation
POST /api/suggest               # Query suggestions
```

### Authentication Flow

1. User authenticates with Cognito
2. Receives JWT token
3. Token validated by API Gateway
4. Lambda functions access Coveo APIs
5. Responses streamed back to UI

## 🔒 Security Features

- **JWT Authentication** with Cognito User Pools
- **API Gateway Authorization** with JWT validation
- **IAM Roles** with least privilege access
- **Permission Boundaries** for enhanced security
- **SSM Parameter Store** for API key and configuration storage
- **VPC Endpoints** for secure AWS service communication

## 📊 Monitoring and Observability

### CloudWatch Integration

- **Lambda Metrics** - Invocation count, duration, errors
- **API Gateway Metrics** - Request count, latency, 4xx/5xx errors
- **Custom Metrics** - Search queries, AI responses, user sessions

### Logging

- **Structured Logging** in all Lambda functions
- **Request/Response Logging** for debugging
- **Error Tracking** with detailed stack traces
- **Performance Monitoring** for optimization

### Dashboards

```bash
# View CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/coveo-workshop"

# Monitor API Gateway
aws apigateway get-rest-apis --query "items[?name=='coveo-workshop-api']"
```

## 🧹 Cleanup

### Complete Cleanup

```bash
# Remove all workshop resources
./scripts/destroy.sh --region us-east-1 --confirm
```

**What gets cleaned up:**
- ✅ CloudFormation stacks (parallel deletion)
- ✅ S3 buckets and all contents
- ✅ Lambda functions and layers
- ✅ API Gateway and routes
- ✅ Cognito User Pool and users
- ✅ IAM roles and policies
- ✅ SSM parameters
- ✅ App Runner services
- ✅ AgentCore Runtimes (MCP Server + Agent)
- ✅ ECR repositories and images
- ✅ Local build artifacts

**Cleanup time:** ~5-8 minutes (70% faster with parallelization)

### Partial Cleanup

```bash
# Clean up specific components
./scripts/destroy.sh --region us-east-1  # Interactive mode
```

### Fix Failed Deployments

```bash
# Handle stacks in ROLLBACK_COMPLETE state
./fix-rollback-stack.sh
```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `COVEO_ORG_ID` | Coveo organization ID | ✅ |
| `COVEO_SEARCH_API_KEY` | Coveo API key with search permissions | ✅ |
| `COVEO_ANSWER_CONFIG_ID` | Coveo Answer configuration ID | ✅ |
| `COVEO_PLATFORM_URL` | Coveo platform URL (default: platform.cloud.coveo.com) | ❌ |
| `COVEO_SEARCH_PIPELINE` | Search pipeline name (default: aws-workshop-pipeline) | ❌ |
| `COVEO_SEARCH_HUB` | Search hub identifier (default: aws-workshop) | ❌ |
| `AWS_REGION` | AWS deployment region (default: us-east-1) | ❌ |
| `API_GATEWAY_URL` | API Gateway URL (auto-populated after deployment) | ❌ |
| `COGNITO_USER_POOL_ID` | Cognito User Pool ID (auto-populated) | ❌ |
| `COGNITO_CLIENT_ID` | Cognito Client ID (auto-populated) | ❌ |
| `TEST_USER_EMAIL` | Test user email for deployment | ❌ |
| `TEST_USER_PASSWORD` | Test user password for deployment | ❌ |
| `PORT` | Local development port (default: 3003) | ❌ |

### Fixed Configuration

For consistency and reliability, some values are fixed:

- **Stack Prefix:** `coveo-workshop`
- **S3 Buckets:** `coveo-workshop-cfn-templates`, `coveo-workshop-ui`
- **ECR Repositories:** `coveo-workshop-coveo-mcp-server`, `coveo-workshop-ui`

### Customization

To customize the workshop:

1. **Update CloudFormation parameters** in `cfn/master.yml`
2. **Modify Lambda environment variables** in templates
3. **Adjust frontend configuration** in `frontend/client/src/config.js`
4. **Update deployment scripts** for different regions or naming

### Getting Help

1. **Check the logs** in CloudWatch
2. **Review CloudFormation events** in AWS Console
3. **Validate prerequisites** with `scripts/validate-before-deploy.sh`
4. **Check AWS service limits** and quotas
5. **Verify Coveo API credentials** and permissions

## 📚 Learning Objectives

By completing this workshop, you will learn:

### AWS Serverless Architecture
- ✅ **Lambda Functions** - Event-driven compute
- ✅ **API Gateway** - RESTful API management
- ✅ **Cognito** - User authentication and authorization
- ✅ **CloudFormation** - Infrastructure as Code
- ✅ **S3 & CloudFront** - Static website hosting
- ✅ **App Runner** - Containerized application deployment

### AI and Search Integration
- ✅ **Coveo Search API** - Enterprise search capabilities
- ✅ **Coveo Answering API** - AI-powered question answering
- ✅ **Bedrock Agents** - Multi-turn AI conversations
- ✅ **AgentCore Tool Calling** - AI agents using external APIs with Coveo MCP Server
- ✅ **Streaming Responses** - Real-time AI interactions

### Modern Web Development
- ✅ **React Hooks** - Modern React patterns
- ✅ **JWT Authentication** - Secure API access
- ✅ **Server-Sent Events** - Real-time updates
- ✅ **Responsive Design** - Mobile-first UI
- ✅ **Error Handling** - Graceful failure management

### DevOps and Deployment
- ✅ **Infrastructure as Code** - Reproducible deployments
- ✅ **CI/CD Patterns** - Automated deployment pipelines
- ✅ **Monitoring and Logging** - Observability best practices
- ✅ **Security Best Practices** - Least privilege access
- ✅ **Cost Optimization** - Serverless cost management

## 🎓 Workshop Labs

### Lab 1: Core Infrastructure
- Deploy AWS serverless infrastructure
- Configure Cognito authentication
- Set up API Gateway and Lambda functions
- Test search, passage retrieval and answer API functionality wth Coveo

### Lab 2: Bedrock Agent Integration
- Create Bedrock Agent with Coveo tools
- Implement multi-turn conversations
- Add memory and context management
- Test passage retrieval API with Bedrock Model summarization to provided a grounded answer
- Test complex AI interactions

### Lab 3: AgentCore Gateway
- Deploy MCP server runtime
- Configure AgentCore Gateway
- Implement streaming responses
- Test Coveo MCP Server for Answer question with tools 
- Compare different backend modes

### Lab 4: Chatbot For Sumamry and Conversational Flow
- Test Chatbot for various backend configurations
- Test Multi Turn Conversations with Bedrock Agent and Agentcore with Coveo MCP tool


## 🔄 Architecture Patterns

### 1. Backend for Frontend (BFF)
```
React UI ←→ Node.js BFF ←→ AWS API Gateway ←→ Lambda Functions
```

### 2. Serverless Microservices
```
API Gateway ←→ [Search Lambda] ←→ Coveo Search API
            ←→ [Answer Lambda] ←→ Coveo Answer API
            ←→ [Agent Lambda]  ←→ Bedrock Agent
```

### 3. Event-Driven Architecture
```
User Action → API Gateway → Lambda → External APIs → Response Stream
```

### 4. Multi-Modal AI Integration
```
User Query → [Route by Intent] → Coveo API (Facts)
                              → Bedrock Agent (Conversation)
                              → AgentCore Gateway (MCP)
```

## 📈 Performance Optimization

### Lambda Optimization
- **Memory allocation** tuned for each function
- **Connection pooling** for external APIs
- **Caching strategies** for frequently accessed data
- **Cold start mitigation** with provisioned concurrency

### API Gateway Optimization
- **Response caching** for static content
- **Request validation** to reduce Lambda invocations
- **Throttling** to protect backend services
- **CORS optimization** for browser performance

### Frontend Optimization
- **Code splitting** for faster initial load
- **Lazy loading** for components and routes
- **Service worker** for offline functionality
- **Bundle optimization** with webpack

## 💰 Cost Optimization

### Serverless Cost Benefits
- **Pay-per-use** - No idle server costs
- **Automatic scaling** - No over-provisioning
- **Managed services** - Reduced operational overhead

### Cost Breakdown (Estimated)

| Service | Monthly Cost | Usage |
|---------|--------------|-------|
| Lambda | $5-15 | 100K requests |
| API Gateway | $3-10 | 100K requests |
| Cognito | $0-5 | <50K MAU |
| S3 | $1-3 | Static hosting |
| App Runner | $10-25 | UI hosting |
| **Total** | **$19-58** | Workshop usage |

## 🔐 Security Best Practices

### Authentication & Authorization
- ✅ **JWT tokens** with short expiration
- ✅ **Cognito User Pools** for user management
- ✅ **API Gateway authorizers** for request validation
- ✅ **IAM roles** with least privilege

### Data Protection
- ✅ **SSM Parameter Store** for API keys and configuration
- ✅ **Encryption at rest** for S3 and databases
- ✅ **TLS encryption** for all API communications


## 🤝 Contributing

We welcome contributions to improve the workshop!

### Development Setup
```bash
# Clone and setup
git clone <repository-url>
cd aws-coveo-workshop

# Install dependencies
npm install

# Run tests
npm test

# Start development
npm run dev
```

### Contribution Guidelines
1. **Fork the repository**
2. **Create a feature branch**
3. **Make your changes**
4. **Add tests** for new functionality
5. **Update documentation**
6. **Submit a pull request**

### Code Standards
- **ESLint** for JavaScript linting
- **Prettier** for code formatting
- **Jest** for unit testing
- **CloudFormation Linter** for template validation

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


## 🚀 Current Status

### ✅ Production Ready Components
- **Core Infrastructure** - CloudFormation templates tested and deployed
- **Lambda Functions** - All 8 Lambda functions operational
- **React UI** - Modern search interface with facet filters
- **Express BFF** - Backend for Frontend with API routing
- **Cognito Authentication** - User pool and JWT validation
- **App Runner Deployment** - Containerized UI deployment
- **AgentCore Runtime** - Serverless agent execution
- **MCP Server** - Tool provider with Coveo integration


### 📦 Deployment Scripts
- ✅ `deploy-complete-workshop.sh` - One-click deployment (8-12 minutes)
- ✅ `destroy.sh` - Complete cleanup (5-8 minutes)
- ✅ `validate-before-deploy.sh` - Prerequisites validation
- ✅ All deployment scripts tested on Windows (Git Bash) and Linux

### 🔧 Configuration
- **Stack Prefix**: `workshop` (fixed for consistency)
- **AWS Region**: `us-east-1` (default, configurable)
- **Deployment Method**: CloudFormation + CodeBuild + App Runner
- **Container Registry**: Amazon ECR

## 📞 Support

For support and questions:

- 📧 **Email:** Contact your workshop instructor
- 📖 **Documentation:** See `/docs` directory for detailed guides
- 🐛 **Issues:** Report issues via GitHub Issues
- 💬 **Discussions:** Use GitHub Discussions for questions

## 🔗 Repository

- **License**: MIT (see LICENSE file)

---

**Happy Learning! 🚀**

Built with ❤️ by the Coveo team.
