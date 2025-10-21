# Workshop UI Frontend

This directory contains the complete frontend implementation for the Workshop UI, including both the React application and the Express BFF (Backend for Frontend) server.

## Directory Structure

```
frontend/
├── server.js                 # Express BFF server (675 lines)
├── package.json              # BFF dependencies
├── package-lock.json         # BFF dependency lock
├── node_modules/             # BFF dependencies (ignored in git)
└── client/                   # React application
    ├── package.json          # React dependencies
    ├── package-lock.json     # React dependency lock
    ├── node_modules/         # React dependencies (ignored in git)
    ├── public/               # Static assets
    ├── src/                  # React source code
    └── build/                # Production build (created by npm run build)
```

## Components

### Express BFF Server (`server.js`)

**Purpose**: Backend for Frontend - Routes React UI requests to API Gateway

**Features**:
- 4 API endpoints: `/api/search`, `/api/passages`, `/api/answer`, `/api/chat`
- 3 backend modes: Coveo, BedrockAgent, CoveoMCP
- Cognito JWT authentication
- Health check endpoint: `/api/health`
- Serves React static build

**Key Functions**:
- `invokeAPIGateway()` - Invokes API Gateway endpoints
- `verifyToken()` - Validates Cognito JWT tokens
- `switch(backendMode)` - Routes to appropriate backend based on mode

### React Application (`client/`)

**Purpose**: Modern search UI with multi-backend support

**Features**:
- Search interface with facets
- Passage retrieval
- Answer generation
- Multi-turn chat
- Backend mode switching (Coveo/BedrockAgent/CoveoMCP)

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

**Note:** Lambda ARNs are no longer needed in frontend .env - the server routes through API Gateway instead.

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

### Coveo Mode (Production Ready)
- All endpoints → Direct Lambda → Coveo API
- Fast, single-turn responses
- No conversation memory

### BedrockAgent Mode (Hybrid)
- `/api/search`, `/api/passages` → Direct Lambda (fast)
- `/api/answer`, `/api/chat` → Bedrock Agent (intelligent, multi-turn)
- Optimized for speed + intelligence balance

### CoveoMCP Mode
- All endpoints → AgentCore Router → MCP Server
- Multi-turn with AgentCore Memory
- Full conversation context

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

See root directory files:
- `deploy-to-aws.ps1` - Windows deployment script
- `deploy-to-aws.sh` - Linux/Mac deployment script
- `DEPLOYMENT_GUIDE.md` - Comprehensive deployment guide
- `DEPLOYMENT_QUICK_REF.md` - Quick reference

## Architecture

```
┌─────────────────┐
│   React UI      │  (frontend/client)
│  (Port 3000)    │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────┐
│   Express BFF                   │  (frontend/server.js)
│   (Port 3003)                   │
│   - Routes to Lambdas           │
│   - Transforms responses        │
│   - Handles auth                │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│   AWS Lambda Functions (5)      │
│   - search-proxy                │
│   - passages-proxy              │
│   - answering-proxy             │
│   - bedrock-agent-chat          │
│   - agentcore-router            │
└─────────────────────────────────┘
```

## Troubleshooting

### Port 3003 already in use
```bash
# Windows
Get-Process -Id (Get-NetTCPConnection -LocalPort 3003).OwningProcess
Stop-Process -Id <PID>

# Linux/Mac
lsof -ti:3003 | xargs kill
```

### React build not found
```bash
cd frontend/client
npm run build
```

### Lambda invocation fails
Check:
1. AWS credentials configured
2. Lambda ARNs correct in `.env`
3. IAM permissions for lambda:InvokeFunction

### CORS errors
Update CORS config in `server.js` line ~21

## File Locations

- **BFF Server**: `frontend/server.js`
- **React App**: `frontend/client/`
- **Environment Variables**: Root `.env` file
- **Docker Build**: Root `Dockerfile`
- **Deployment Scripts**: Root directory
- **Documentation**: Root directory

## Related Documentation

- `../DEPLOYMENT_GUIDE.md` - Full deployment instructions
- `../TEST_RESULTS.md` - Test results and known issues
- `../COVEO_API_PAYLOADS.md` - Lambda input/output contracts
- `../README_IMPLEMENTATION.md` - Implementation summary

## Version

- **BFF Server**: 675 lines (optimized)
- **React App**: Latest build with multi-backend support
- **Node.js**: 18.x
- **Docker**: Multi-stage optimized build

## Status

✅ **Production Ready** (Coveo mode)  
⚠️ BedrockAgent mode needs Lambda config fix  
⏸️ CoveoMCP mode needs MCP server setup

---

**Note**: This consolidated `/frontend` directory replaces the previous `/client` and `/ui` directories. All UI-related code is now in one place for easier maintenance.
