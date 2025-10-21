# Workshop UI Frontend

This directory contains the complete frontend implementation for the AWS Coveo Workshop, including both the React application and the Express BFF (Backend for Frontend) server. The UI features a modern search interface with facet filters, real-time results, and support for three different backend architectures.

## Directory Structure

```
frontend/
├── server.js                 # Express BFF server
├── package.json              # BFF dependencies (express, aws-sdk, etc.)
├── package-lock.json         # BFF dependency lock
├── node_modules/             # BFF dependencies (not in git)
├── Dockerfile                # Multi-stage Docker build
├── README.md                 # This file
└── client/                   # React application
    ├── package.json          # React dependencies
    ├── package-lock.json     # React dependency lock
    ├── node_modules/         # React dependencies (not in git)
    ├── .env                  # React environment variables
    ├── public/               # Static assets
    │   ├── index.html        # HTML template
    │   └── manifest.json     # PWA manifest
    ├── src/                  # React source code
    │   ├── components/       # React components
    │   │   ├── SearchHeader.js      # Search bar with centered clear button
    │   │   ├── SearchResults.js     # Results display with load more
    │   │   ├── Sidebar.js           # Scrollable facet filters
    │   │   ├── AuthProvider.js      # Cognito authentication
    │   │   ├── LoginButton.js       # Login/logout UI
    │   │   ├── QuickViewModal.js    # Document preview modal
    │   │   └── ChatBot.js           # Chat interface
    │   ├── services/
    │   │   └── api.js        # API client (search, passages, answer, chat)
    │   ├── App.js            # Main application component
    │   ├── index.js          # React entry point
    │   └── index.css         # Global styles
    └── build/                # Production build (created by npm run build)
```

## Components

### Express BFF Server (`server.js`)

**Purpose**: Backend for Frontend - Proxies React UI requests to AWS API Gateway

**Features**:
- 5 API endpoints: `/api/search`, `/api/passages`, `/api/answer`, `/api/chat`, `/api/suggest`
- 3 backend modes: Coveo, BedrockAgent, CoveoMCP
- Cognito JWT token validation
- Health check endpoint: `/api/health`
- Serves React static build from `client/build/`

**Key Functions**:
- Routes all requests to **API Gateway** (not direct Lambda invocation)
- `verifyToken()` - Validates Cognito JWT tokens
- `switch(backendMode)` - Routes to appropriate API Gateway endpoint based on mode
- Handles CORS and request/response transformation

### React Application (`client/`)

**Purpose**: Modern, responsive search UI with multi-backend support

**Features**:
- 🔍 **Search interface** with real-time results
- 📊 **Scrollable facet filters** (Project, Document Type, etc.)
- ✨ **Centered clear button** in search box
- 📄 **Passage retrieval** with quick view
- 🤖 **AI answer generation** with citations
- 💬 **Multi-turn chat** interface
- 🔄 **Backend mode switching** (Coveo/BedrockAgent/CoveoMCP)
- 🔐 **Cognito authentication** with JWT tokens
- 📱 **Responsive design** for mobile and desktop
- ⚡ **Load more** functionality for search results

## Development

### Running Locally

#### Option 1: Run both together
```bash
cd frontend
npm run dev
```

This starts:
- Express BFF server on `http://localhost:3003`
- React dev server on `http://localhost:3000` (proxies to 3003)

#### Option 2: Run separately

**Terminal 1 - BFF Server:**
```bash
cd frontend
npm run server
```

**Terminal 2 - React App:**
```bash
cd frontend/client
npm start
```

### Building for Production

```bash
# Build React app
cd frontend/client
npm run build

# Serve with Express
cd ..
npm start
```

The Express server will serve the React build from `client/build/`.

## Docker Build

The Dockerfile uses a multi-stage build:

1. **Stage 1**: Build React app (`frontend/client`)
2. **Stage 2**: Install BFF dependencies (`frontend/`)
3. **Stage 3**: Production image with both

```bash
# Build Docker image
docker build -t workshop-ui-bff:latest .

# Run container
docker run -p 3003:3003 --env-file .env workshop-ui-bff:latest
```

## Environment Variables

All configuration is in the root `.env` file:

```bash
# Server Configuration
PORT=3003
NODE_ENV=development

# Coveo API Configuration
COVEO_ORG_ID=your-coveo-org-id
COVEO_SEARCH_API_KEY=<your-api-key>
COVEO_PLATFORM_URL=https://platform.cloud.coveo.com
COVEO_SEARCH_PIPELINE=aws-workshop-pipeline
COVEO_SEARCH_HUB=aws-workshop
COVEO_ANSWER_CONFIG_ID=<your-answer-config-id>
COVEO_RESULTS_PER_PAGE=20

# AWS Configuration
AWS_REGION=us-east-1
API_GATEWAY_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com

# Cognito Configuration
COGNITO_USER_POOL_ID=us-east-1_XXXXXXXXX
COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
COGNITO_REGION=us-east-1
COGNITO_DOMAIN=workshop-auth
```

**Note:** The BFF server routes all requests through API Gateway. No direct Lambda invocation is needed.

## Request Flow

**Important:** The BFF server does NOT invoke Lambda functions directly. All requests flow through API Gateway:

```
User Browser → React UI → Express BFF → API Gateway → Lambda → External APIs
```

1. **React UI** sends HTTP request to BFF server
2. **Express BFF** validates JWT token and forwards to API Gateway
3. **API Gateway** authorizes request and invokes appropriate Lambda
4. **Lambda** processes request and calls external APIs (Coveo, Bedrock, etc.)
5. **Response** flows back through the same chain

## API Endpoints

### Health Check
```bash
GET /api/health
```

Returns server status and configuration.

### Search
```bash
POST /api/search
{
  "query": "cloud computing",
  "backendMode": "coveo",  # or "bedrockAgent" or "coveoMCP"
  "numberOfResults": 10
}
```

### Passages
```bash
POST /api/passages
{
  "query": "AWS Lambda",
  "backendMode": "coveo",
  "numberOfPassages": 5
}
```

### Answer
```bash
POST /api/answer
{
  "query": "What is cryptography?",
  "backendMode": "coveo"
}
```

### Chat
```bash
POST /api/chat
{
  "message": "Tell me about cloud computing",
  "backendMode": "coveo",
  "sessionId": "optional-session-id"
}
```

## Backend Modes

The BFF server routes all requests through **API Gateway**, which then invokes the appropriate Lambda functions:

### Coveo Mode (Production Ready)
- BFF → API Gateway → Lambda (search-proxy, passages-proxy, answering-proxy) → Coveo API
- Fast, single-turn responses
- Direct Coveo API integration

### BedrockAgent Mode (Multi-turn AI)
- BFF → API Gateway → Lambda (agentcore-runtime) → AgentCore Runtime → Bedrock
- Multi-turn conversations with streaming responses
- AgentCore Memory for conversation context

### CoveoMCP Mode (Tool-based)
- BFF → API Gateway → Lambda (agentcore-runtime) → AgentCore Runtime → MCP Server → Coveo API
- Tool-based orchestration with MCP protocol
- Extensible architecture for custom tools

## Testing

```bash
# Test health endpoint
curl http://localhost:3003/api/health

# Test search (Coveo mode)
curl -X POST http://localhost:3003/api/search \
  -H "Content-Type: application/json" \
  -d '{"query":"cloud computing","backendMode":"coveo","numberOfResults":3}'

# Test chat (Coveo mode)
curl -X POST http://localhost:3003/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"What is cryptography?","backendMode":"coveo"}'
```

## Deployment

The frontend is deployed to **AWS App Runner** as a containerized application.

### Deployment Scripts

Located in the root `scripts/` directory:
- `deploy-complete-workshop.sh` - Complete one-click deployment (includes UI)
- `deploy-ui-apprunner.sh` - Deploy UI to App Runner
- `destroy.sh` - Complete cleanup including UI

### Deployment Process

1. **Build Docker image** - Multi-stage build (React + Express)
2. **Push to ECR** - Amazon Elastic Container Registry
3. **Deploy to App Runner** - Automatic deployment and scaling
4. **Update Cognito callbacks** - Configure OAuth redirect URLs

### Manual Deployment

```bash
# Deploy UI to App Runner
cd scripts
./deploy-ui-apprunner.sh --region us-east-1
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    React UI                             │
│                 (frontend/client)                       │
│              Port 3000 (dev) / 3003 (prod)              │
│  • Search Interface  • Facet Filters  • Auth UI        │
└────────────────────────┬────────────────────────────────┘
                         │ HTTP Requests
                         ▼
┌─────────────────────────────────────────────────────────┐
│                  Express BFF Server                     │
│                 (frontend/server.js)                    │
│                     Port 3003                           │
│  • JWT Validation  • CORS Handling  • Request Routing  │
│  • Serves React Build  • Health Check                  │
└────────────────────────┬────────────────────────────────┘
                         │ HTTPS to API Gateway
                         ▼
┌─────────────────────────────────────────────────────────┐
│                   AWS API Gateway                       │
│  • /api/search  • /api/passages  • /api/answer         │
│  • /api/chat    • /api/suggest   • /health             │
│  • JWT Authorizer  • Request Validation                │
└────────────────────────┬────────────────────────────────┘
                         │ Invokes Lambda Functions
                         ▼
┌─────────────────────────────────────────────────────────┐
│                  AWS Lambda Functions                   │
│  • search-proxy          → Coveo Search API             │
│  • passages-proxy        → Coveo Passages API           │
│  • answering-proxy       → Coveo Answering API          │
│  • query-suggest-proxy   → Coveo Query Suggest API      │
│  • html-proxy            → Coveo HTML API               │
│  • agentcore-runtime     → AgentCore Runtime/MCP        │
│  • bedrock-agent-chat    → Bedrock Agent                │
└─────────────────────────────────────────────────────────┘
```

**Key Points:**
- BFF **never** calls Lambda directly - all requests go through API Gateway
- API Gateway handles authentication, authorization, and request validation
- Lambda functions are invoked by API Gateway, not by the BFF
- This architecture provides better security, monitoring, and scalability

## File Locations

- **BFF Server**: `frontend/server.js`
- **React App**: `frontend/client/`
- **Environment Variables**: Root `.env` file
- **Docker Build**: Root `Dockerfile`
- **Deployment Scripts**: Root directory
- **Documentation**: Root directory

## Related Documentation

- `../README.md` - Main project documentation
- `.env.example` - Environment variable template (in root directory)

## Technology Stack

- **BFF Server**: Express.js with AWS SDK
- **React App**: React 18 with Hooks
- **Styling**: Styled Components with Framer Motion animations
- **Authentication**: AWS Cognito with JWT
- **API Client**: Axios for HTTP requests
- **Node.js**: 18.x LTS
- **Docker**: Multi-stage build for optimized images
- **Deployment**: AWS App Runner with auto-scaling

## Recent Updates

### UI Improvements
- ✅ **Scrollable facet filters** with custom scrollbar styling
- ✅ **Load more functionality** for search results
- ✅ **Quick view modal** for document preview
- ✅ **Responsive design** improvements

### Backend Integration
- ✅ **Three backend modes** fully implemented
- ✅ **AgentCore Runtime** integration
- ✅ **MCP Server** support
- ✅ **Streaming responses** for AI answers

## Status

✅ **Production Ready** - All three backend modes operational  
✅ **Coveo Mode** - Direct API integration (fast, single-turn)  
✅ **BedrockAgent Mode** - AgentCore Runtime with streaming  
✅ **CoveoMCP Mode** - MCP Server with tool orchestration

---

**Note**: This is the complete frontend implementation for the AWS Coveo Workshop. All UI components, BFF server, and Docker configuration are in this directory.
