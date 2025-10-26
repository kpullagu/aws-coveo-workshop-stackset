# AWS Coveo Workshop - Multi-Account StackSets Deployment

[![AWS](https://img.shields.io/badge/AWS-StackSets-orange)](https://aws.amazon.com/)
[![Coveo](https://img.shields.io/badge/Coveo-Search%20API-blue)](https://www.coveo.com/)
[![Bedrock](https://img.shields.io/badge/AWS-Bedrock%20AgentCore-purple)](https://aws.amazon.com/bedrock/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A production-ready, multi-account AWS workshop demonstrating AI-powered search and answering using Coveo's platform integrated with AWS Bedrock AgentCore Runtime, deployed via AWS CloudFormation StackSets across multiple accounts in an AWS Organization.

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Project Structure](#-project-structure)
- [Deployment Process](#-deployment-process)
- [Configuration](#-configuration)
- [Testing](#-testing)
- [Cleanup](#-cleanup)
- [Troubleshooting](#-troubleshooting)
- [Documentation](#-documentation)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🎯 Overview

This workshop deploys a complete AI-powered search solution across multiple AWS accounts using **AWS CloudFormation StackSets** with **SERVICE_MANAGED** permissions. It demonstrates enterprise-scale deployment patterns with:

- **Multi-Account Architecture** - Deploy to 10+ AWS accounts simultaneously
- **AWS Organizations Integration** - Automatic account discovery and deployment
- **Bedrock AgentCore Runtime** - Serverless AI agent execution with streaming
- **MCP Server Integration** - Model Context Protocol for tool orchestration
- **Coveo Search Platform** - Enterprise search with AI-powered relevance
- **Full Observability** - X-Ray tracing, CloudWatch Logs, session correlation
- **Production-Ready** - Security, monitoring, and operational best practices

### Key Features

✅ **One-Command Deployment** - Deploy entire infrastructure with single script
✅ **Multi-Account Support** - Deploy to unlimited AWS accounts via StackSets
✅ **Cross-Account Replication** - S3 and ECR replication for Lambda packages and images
✅ **Automated Configuration** - SSM parameters, Cognito, and observability setup
✅ **Complete Observability** - X-Ray, CloudWatch Logs, Bedrock model invocation logging
✅ **Secure by Default** - IAM roles, encryption, least privilege access
✅ **Easy Cleanup** - Nuclear option for complete resource removal

---

## 🏗️ Architecture

### High-Level Multi-Account Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Master/Management Account                      │
│  • ECR Repositories (MCP Server, Agent, UI images)                 │
│  • S3 Bucket (Lambda packages, CloudFormation templates)           │
│  • Lambda Layer (shared dependencies)                              │
│  • StackSet Management (deployment orchestration)                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ AWS Organizations
                             │ StackSets Deployment
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Child Accounts (10+ accounts)                    │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ Layer 1: Prerequisites                                       │ │
│  │  • S3 Buckets (replicated from master)                      │ │
│  │  • ECR Repositories (cross-account pull)                    │ │
│  │  • IAM Roles (execution, replication)                       │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ Layer 2: Core Infrastructure                                │ │
│  │  • Lambda Functions (search, passages, answering)           │ │
│  │  • API Gateway (RESTful API)                                │ │
│  │  • Cognito User Pool (authentication)                       │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ Layer 3: AI Services                                        │ │
│  │  • Bedrock AgentCore MCP Runtime                            │ │
│  │  • Bedrock AgentCore Agent Runtime                          │ │
│  │  • SSM Parameters (configuration)                           │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ Layer 4: UI                                                 │ │
│  │  • App Runner Service (React UI + Express BFF)              │ │
│  │  • CloudWatch Logs (application logs)                       │ │
│  └──────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Deployment Flow

```
1. Master Account Setup
   ├─ Create ECR repositories
   ├─ Build Docker images (MCP Server, Agent, UI)
   ├─ Create Lambda Layer
   └─ Package Lambda functions

2. Layer 1 Deployment (Prerequisites)
   ├─ Deploy to all accounts via StackSets
   ├─ Create S3 buckets in each account
   ├─ Setup S3 replication from master
   └─ Wait for replication to complete

3. Layer 2 Deployment (Core)
   ├─ Deploy Lambda functions
   ├─ Create API Gateway
   ├─ Setup Cognito User Pool
   └─ Configure IAM roles

4. Layer 3 Deployment (AI Services)
   ├─ Deploy AgentCore MCP Runtime
   ├─ Deploy AgentCore Agent Runtime
   ├─ Seed SSM parameters
   └─ Enable Bedrock logging

5. Layer 4 Deployment (UI)
   ├─ Deploy App Runner services
   ├─ Configure Cognito callbacks
   └─ Enable X-Ray tracing

6. Post-Deployment Configuration
   ├─ Create Cognito test users
   ├─ Collect deployment information
   └─ Enable observability features
```

---


## 📦 Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| **AWS CLI** | v2.x | AWS service interaction |
| **Docker** | 20.x+ | Building container images |
| **jq** | 1.6+ | JSON processing in scripts |
| **Bash** | 4.x+ | Running deployment scripts |
| **Git** | 2.x+ | Version control |

### AWS Requirements

1. **AWS Organizations**
   - Active AWS Organization
   - At least one Organizational Unit (OU)
   - Child accounts in the OU

2. **IAM Permissions** (Master Account)
   - `organizations:*` - Manage Organizations
   - `cloudformation:*` - Create StackSets
   - `iam:*` - Create roles and policies
   - `ecr:*` - Manage ECR repositories
   - `s3:*` - Manage S3 buckets
   - `lambda:*` - Create Lambda functions and layers

3. **Cross-Account Role**
   - `OrganizationAccountAccessRole` in all child accounts
   - Trust relationship with master account
   - Administrator access in child accounts

4. **Service Quotas**
   - StackSets: 100 per region (default)
   - Lambda concurrent executions: 1000 (default)
   - API Gateway: 10,000 requests/second (default)

### Coveo Requirements

1. **Coveo Organization**
   - Active Coveo organization
   - Search API key with permissions
   - Answer configuration ID

2. **Indexed Content**
   - At least one search pipeline
   - Indexed content sources
   - Answer configuration setup

### Installation

#### macOS/Linux
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install jq
sudo apt-get install jq  # Ubuntu/Debian
brew install jq          # macOS

# Install Docker
# Follow: https://docs.docker.com/engine/install/
```

#### Windows
```powershell
# Install AWS CLI
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi

# Install jq
choco install jq

# Install Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop
```

---

## 🚀 Quick Start

### Step 1: Clone Repository

```bash
git clone https://github.com/your-org/aws-cove-workshop-stackset.git
cd aws-coveo-workshop
```

### Step 2: Configure Environment

```bash
# Copy the example configuration
cp .env.stacksets.example .env.stacksets

# Edit with your values
nano .env.stacksets
```

**Required Configuration:**
```bash
# AWS Organizations
OU_ID=ou-xxxx-xxxxxxxx                    # Your OU ID
MASTER_ACCOUNT_ID=123456789012            # Master account ID
AWS_REGION=us-east-1                      # Deployment region
STACK_PREFIX=workshop                     # Resource prefix

# Coveo Configuration
COVEO_ORG_ID=your-org-id
COVEO_SEARCH_API_KEY=xx00000000-0000-0000-0000-000000000000
COVEO_ANSWER_CONFIG_ID=00000000-0000-0000-0000-000000000000

# Test User (Optional)
TEST_USER_EMAIL=workshop-user@example.com
TEST_USER_PASSWORD=ChangeMe123!
```

### Step 3: Deploy

```bash
# One-command deployment
bash scripts/stacksets/deploy-all-stacksets.sh
```

**Deployment Time:** 45-60 minutes

**What Gets Deployed:**
- ✅ Master account setup (ECR, S3, Lambda Layer)
- ✅ Layer 1 to 10+ accounts (S3, ECR, IAM)
- ✅ Layer 2 to 10+ accounts (Lambda, API Gateway, Cognito)
- ✅ Layer 3 to 10+ accounts (AgentCore Runtimes)
- ✅ Layer 4 to 10+ accounts (App Runner UI)
- ✅ Observability (X-Ray, CloudWatch, Bedrock logging)
- ✅ Post-deployment configuration

### Step 4: Access Application

After deployment completes, you'll see:

```
========================================
DEPLOYMENT COMPLETE!
========================================

Deployment Information:
  Account: 123456789012
  Region: us-east-1
  UI URL: https://xxxxx.us-east-1.awsapprunner.com
  API URL: https://xxxxx.execute-api.us-east-1.amazonaws.com

Test Credentials:
  Email: workshop-user@example.com
  Password: ChangeMe123!

Next Steps:
  1. Open the UI URL in your browser
  2. Login with test credentials
  3. Try searching for "cryptocurrency" or "travel safety"
```

---


## 📁 Project Structure

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
├── 📁 Instructor/                             # Instructor materials (gitignored)
├── 📁 Lab1/                                   # Lab 1 materials (gitignored)
├── 📁 Lab2/                                   # Lab 2 materials (gitignored)
├── 📁 Lab3/                                   # Lab 3 materials (gitignored)
├── 📁 Lab4/                                   # Lab 4 materials (gitignored)
│
├── .dockerignore                              # Docker ignore rules
├── .env.stacksets.example                     # Config template ✅ COMMIT
├── .env.stacksets                             # Your config ❌ GITIGNORED
├── .env.example                               # Frontend config template ✅ COMMIT
├── .env.template                              # Environment template
├── .env                                       # Frontend config ❌ GITIGNORED
├── .gitignore                                 # Git ignore rules
├── LICENSE                                    # MIT License
├── README.md                                  # This file
└── SETUP_GUIDE.md                             # Setup instructions
```

### Key Directories

| Directory | Purpose |
|-----------|---------|
| `cfn/stacksets/` | CloudFormation StackSet templates for multi-account deployment |
| `scripts/stacksets/` | Bash scripts for deployment, configuration, and cleanup |
| `coveo-agent/` | Bedrock AgentCore Agent application (Python) |
| `coveo-mcp-server/` | MCP Server for tool orchestration (Python) |
| `frontend/` | React UI with Express BFF (Node.js) |
| `lambdas/` | AWS Lambda functions (Python) |
| `docs/` | Comprehensive documentation |

---


## 🔧 Deployment Process

### Complete Deployment Flow

The `deploy-all-stacksets.sh` script orchestrates the entire deployment:

```bash
bash scripts/stacksets/deploy-all-stacksets.sh
```

#### Step-by-Step Breakdown

**Step 1: Master Account Setup** (5 minutes)
```bash
# Creates ECR repositories in master account
bash scripts/stacksets/01-setup-master-ecr.sh
```
- Creates ECR repositories for MCP Server, Agent, and UI
- Sets up repository policies for cross-account access

**Step 2: Build Docker Images** (10 minutes)
```bash
# Build and push MCP Server image
bash scripts/stacksets/02-build-push-mcp-image.sh

# Build and push Agent image
bash scripts/stacksets/02b-build-push-agent-image.sh

# Build and push UI image
bash scripts/stacksets/03-build-push-ui-image.sh
```
- Builds Docker images locally
- Pushes to master account ECR
- Tags with `latest` and commit SHA

**Step 3: Create Lambda Layer** (3 minutes)
```bash
bash scripts/stacksets/04-create-shared-lambda-layer.sh
```
- Installs Python dependencies
- Creates Lambda Layer in master account
- Grants permissions to all child accounts

**Step 4: Package Lambda Functions** (2 minutes)
```bash
bash scripts/stacksets/05-package-lambdas.sh
```
- Packages all Lambda functions
- Uploads to master S3 bucket
- Prepares for replication to child accounts

**Step 5: Deploy Layer 1 - Prerequisites** (5 minutes)
```bash
bash scripts/stacksets/10-deploy-layer1-prerequisites.sh
```
- Creates StackSet for Layer 1
- Deploys to all accounts in OU
- Creates S3 buckets, ECR repos, IAM roles

**Step 6: Setup S3 Replication** (15 minutes)
```bash
bash scripts/stacksets/06-setup-s3-replication-v2.sh
```
- Configures S3 replication from master to child accounts
- Waits for Lambda packages to replicate
- Verifies replication with probe file

**Step 7: Seed SSM Parameters** (2 minutes)
```bash
bash scripts/stacksets/07-seed-ssm-parameters.sh
```
- Creates SSM parameters in all accounts
- Stores Coveo API keys, configuration
- Required before Layer 2 deployment

**Step 8: Deploy Layer 2 - Core Infrastructure** (8 minutes)
```bash
bash scripts/stacksets/11-deploy-layer2-core.sh
```
- Deploys Lambda functions
- Creates API Gateway
- Sets up Cognito User Pool

**Step 9: Deploy Layer 3 - AI Services** (10 minutes)
```bash
bash scripts/stacksets/12-deploy-layer3-ai-services.sh
```
- Deploys AgentCore MCP Runtime
- Deploys AgentCore Agent Runtime
- Creates SSM parameters for runtimes

**Step 10: Seed Agent SSM Parameters** (2 minutes)
```bash
bash scripts/stacksets/12b-seed-agent-ssm-parameters.sh
```
- Creates Agent-specific SSM parameters
- Stores MCP Runtime ARN, model ID

**Step 11: Enable Bedrock Logging** (3 minutes)
```bash
bash scripts/stacksets/enable-bedrock-model-invocation-logging.sh
```
- Enables Bedrock model invocation logging
- Configures CloudWatch Logs destination

**Step 12: Deploy Layer 4 - UI** (8 minutes)
```bash
bash scripts/stacksets/13-deploy-layer4-ui.sh
```
- Deploys App Runner services
- Configures auto-scaling
- Sets up CloudWatch Logs

**Step 13: Enable X-Ray Ingestion** (3 minutes)
```bash
bash scripts/stacksets/enable-xray-cloudwatch-ingestion.sh
```
- Enables X-Ray span ingestion to CloudWatch
- Configures sampling rules
- Sets up log groups

**Step 14: Post-Deployment Configuration** (5 minutes)
```bash
bash scripts/stacksets/14-post-deployment-config.sh
```
- Creates Cognito test users
- Configures Cognito callback URLs
- Collects deployment information
- Generates CSV with all account details

### Deployment Timeline

```
Total Time: 45-60 minutes

Master Setup:        ████░░░░░░░░░░░░░░░░  5 min
Build Images:        ████████████░░░░░░░░ 10 min
Lambda Layer:        ███░░░░░░░░░░░░░░░░░  3 min
Package Lambdas:     ██░░░░░░░░░░░░░░░░░░  2 min
Layer 1 Deploy:      █████░░░░░░░░░░░░░░░  5 min
S3 Replication:      ███████████████░░░░░ 15 min
SSM Parameters:      ██░░░░░░░░░░░░░░░░░░  2 min
Layer 2 Deploy:      ████████░░░░░░░░░░░░  8 min
Layer 3 Deploy:      ██████████░░░░░░░░░░ 10 min
Agent SSM:           ██░░░░░░░░░░░░░░░░░░  2 min
Bedrock Logging:     ███░░░░░░░░░░░░░░░░░  3 min
Layer 4 Deploy:      ████████░░░░░░░░░░░░  8 min
X-Ray Setup:         ███░░░░░░░░░░░░░░░░░  3 min
Post-Config:         █████░░░░░░░░░░░░░░░  5 min
```

### Parallel Deployment

The script deploys to multiple accounts in parallel:
- **StackSet Operations** - Deploys to all accounts simultaneously
- **Max Concurrent** - 10 accounts at a time (configurable)
- **Failure Tolerance** - Continues if 5 accounts fail (configurable)

---

