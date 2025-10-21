#!/bin/bash

# =============================================================================
# Complete Workshop Deployment - Orchestration Script
# =============================================================================
# This script orchestrates the complete workshop deployment by calling
# individual deployment scripts in the correct order.
#
# Architecture:
# UI (React + Express BFF) → API Gateway → Lambda → Agent Runtime → MCP Runtime → Coveo API
# =============================================================================

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root directory
cd "$PROJECT_ROOT"

# Load environment variables from .env if it exists
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
elif [ -f "config/.env" ]; then
    set -a
    source config/.env
    set +a
fi

# Fixed configuration
STACK_PREFIX="workshop"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    local message="$1"
    local status="$2"
    
    if [ "$status" = "INFO" ]; then
        echo -e "${BLUE}ℹ️  $message${NC}"
    elif [ "$status" = "SUCCESS" ]; then
        echo -e "${GREEN}✅ $message${NC}"
    elif [ "$status" = "WARNING" ]; then
        echo -e "${YELLOW}⚠️  $message${NC}"
    elif [ "$status" = "ERROR" ]; then
        echo -e "${RED}❌ $message${NC}"
    fi
}

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Complete Workshop Deployment${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Stack Prefix: $STACK_PREFIX (fixed)"
echo -e "  AWS Region: $AWS_REGION"
echo ""
echo -e "${YELLOW}Deployment Sequence:${NC}"
echo -e "  → Prerequisites validation"
echo -e "  → Main infrastructure (API Gateway, Lambda, Cognito)"
echo -e "  → MCP Server (Tool Provider)"
echo -e "  → Agent Runtime (Orchestrator)"
echo -e "  → UI Application (React + Express BFF)"
echo -e "  → Cognito configuration (test user, callback URLs)"
echo ""
echo -e "${YELLOW}Estimated time: 8-12 minutes${NC}"
echo ""

# Confirm deployment
read -p "Continue with complete deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deployment cancelled by user" "WARNING"
    exit 0
fi

echo ""

# =============================================================================
# Validate Prerequisites
# =============================================================================
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Validating Prerequisites${NC}"
echo -e "${BLUE}==============================================================================${NC}"
print_status "Checking AWS CLI, Docker, and environment variables..." "INFO"
echo ""

if [ -f "scripts/validate-before-deploy.sh" ]; then
    bash scripts/validate-before-deploy.sh
    if [ $? -ne 0 ]; then
        print_status "Prerequisites validation failed" "ERROR"
        exit 1
    fi
else
    print_status "Validation script not found: scripts/validate-before-deploy.sh" "ERROR"
    exit 1
fi

echo ""

# =============================================================================
# Deploy Main Infrastructure
# =============================================================================
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Deploying Main Infrastructure${NC}"
echo -e "${BLUE}==============================================================================${NC}"
print_status "Deploying CloudFormation stacks, Lambda functions, API Gateway..." "INFO"
print_status "Note: Cognito user pool created but test user added later" "INFO"
echo ""

bash scripts/deploy-main-infra.sh --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    print_status "Main infrastructure deployment failed" "ERROR"
    exit 1
fi

print_status "Main infrastructure deployed successfully" "SUCCESS"
echo ""

# =============================================================================
# Deploy MCP Server (Tool Provider)
# =============================================================================
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Deploying MCP Server (Tool Provider)${NC}"
echo -e "${BLUE}==============================================================================${NC}"
print_status "Creating MCP runtime with Coveo API tools..." "INFO"
print_status "CodeBuild will generate and build the Docker image" "INFO"
echo ""

bash scripts/deploy-mcp.sh

if [ $? -ne 0 ]; then
    print_status "MCP Server deployment failed" "ERROR"
    exit 1
fi

print_status "MCP Server deployed successfully" "SUCCESS"
echo ""

# =============================================================================
# Deploy Agent Runtime (Orchestrator)
# =============================================================================
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Deploying Agent Runtime (Orchestrator)${NC}"
echo -e "${BLUE}==============================================================================${NC}"
print_status "Creating Agent that orchestrates MCP tool calls with Bedrock..." "INFO"
print_status "Building Docker image locally and deploying to AgentCore Runtime" "INFO"
echo ""

bash scripts/deploy-agent.sh

if [ $? -ne 0 ]; then
    print_status "Agent Runtime deployment failed" "ERROR"
    exit 1
fi

print_status "Agent Runtime deployed successfully" "SUCCESS"
echo ""

# =============================================================================
# Deploy UI (Frontend + BFF)
# =============================================================================
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Deploying UI Application${NC}"
echo -e "${BLUE}==============================================================================${NC}"
print_status "Building and deploying React frontend + Express BFF to App Runner..." "INFO"
echo ""

bash scripts/deploy-ui-apprunner.sh --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    print_status "UI deployment failed" "ERROR"
    exit 1
fi

print_status "UI deployed successfully" "SUCCESS"
echo ""

# =============================================================================
# Configure Cognito (Final Step)
# =============================================================================
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Configuring Cognito Authentication${NC}"
echo -e "${BLUE}==============================================================================${NC}"
print_status "Setting up test user and callback URLs..." "INFO"
echo ""

# Get Cognito info from master stack
COGNITO_USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

COGNITO_CLIENT_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

COGNITO_HOSTED_UI_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='CognitoHostedUIUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

APP_RUNNER_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-ui-apprunner" \
    --query "Stacks[0].Outputs[?OutputKey=='AppRunnerServiceUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -z "$COGNITO_USER_POOL_ID" ] || [ -z "$COGNITO_CLIENT_ID" ]; then
    print_status "Failed to retrieve Cognito configuration" "ERROR"
    exit 1
fi

# Create test user (read from .env or use defaults)
TEST_USER_EMAIL="${TEST_USER_EMAIL:-testuser@example.com}"
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-TempPassword123!}"

print_status "Creating test user: $TEST_USER_EMAIL (from .env or default)" "INFO"
aws cognito-idp admin-create-user \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$TEST_USER_EMAIL" \
    --user-attributes \
        Name=email,Value=$TEST_USER_EMAIL \
        Name=email_verified,Value=true \
    --message-action SUPPRESS \
    --region "$AWS_REGION" 2>/dev/null || print_status "User may already exist" "WARNING"

# Set permanent password
print_status "Setting permanent password: $TEST_USER_PASSWORD" "INFO"
aws cognito-idp admin-set-user-password \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$TEST_USER_EMAIL" \
    --password "$TEST_USER_PASSWORD" \
    --permanent \
    --region "$AWS_REGION" 2>/dev/null

print_status "Test user configured successfully" "SUCCESS"

# Update Cognito callback URLs
if [ -n "$APP_RUNNER_URL" ] && [ "$APP_RUNNER_URL" != "Not available" ]; then
    print_status "Updating Cognito callback URLs with App Runner domain..." "INFO"
    
    if [ -f "scripts/update-cognito-callbacks.sh" ]; then
        bash scripts/update-cognito-callbacks.sh --stack-prefix "$STACK_PREFIX" --region "$AWS_REGION"
        print_status "Callback URLs updated successfully" "SUCCESS"
    else
        print_status "Callback update script not found, skipping..." "WARNING"
    fi
fi

echo ""

# =============================================================================
# Retrieve Deployment Information
# =============================================================================
print_status "Retrieving deployment information..." "INFO"

API_GATEWAY_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiBaseUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "Not available")

MCP_RUNTIME_ARN=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/coveo/mcp-runtime-arn" \
    --query "Parameter.Value" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "Not available")

AGENT_RUNTIME_ARN=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/coveo/agent-runtime-arn" \
    --query "Parameter.Value" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "Not available")

# =============================================================================
# Final Summary
# =============================================================================
echo ""
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${GREEN}🎉 Workshop Deployment Complete!${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""
echo -e "${GREEN}✅ Infrastructure:${NC} All AWS resources deployed"
echo -e "${GREEN}✅ AgentCore Runtime:${NC} MCP and Agent runtimes ready"
echo -e "${GREEN}✅ UI Application:${NC} React + Express BFF on App Runner"
echo -e "${GREEN}✅ Authentication:${NC} Cognito configured with test user"
echo ""
echo -e "${YELLOW}🌐 Application URLs:${NC}"
echo -e "  Frontend: $APP_RUNNER_URL"
echo -e "  API Gateway: $API_GATEWAY_URL"
echo -e "  Cognito Login: $COGNITO_HOSTED_UI_URL"
echo ""
echo -e "${YELLOW}🔐 Test Credentials:${NC}"
echo -e "  Email: $TEST_USER_EMAIL"
echo -e "  Password: $TEST_USER_PASSWORD"
echo -e "  (Permanent password - no change required)"
echo ""
echo -e "${YELLOW}🏗️ Architecture:${NC}"
echo -e "  UI → API Gateway → Lambda → Agent Runtime → MCP Runtime → Coveo API"
echo ""
echo -e "${YELLOW}🤖 Runtime Information:${NC}"
echo -e "  MCP Runtime ARN: $MCP_RUNTIME_ARN"
echo -e "  Agent Runtime ARN: $AGENT_RUNTIME_ARN"
echo ""
echo -e "${YELLOW}🧪 Next Steps:${NC}"
echo -e "  1. Open: $APP_RUNNER_URL"
echo -e "  2. Click 'Login' and use test credentials above"
echo -e "  3. Test all three backend modes:"
echo -e "     • Coveo (direct API)"
echo -e "     • BedrockAgent (with Bedrock Agent)"
echo -e "     • coveoMCP (with MCP Server)"
echo ""
echo -e "${YELLOW}📋 Workshop Ready!${NC}"
echo -e "  All infrastructure deployed and configured"
echo -e "  Ready for workshop attendees"
echo ""

# Save deployment info
cat > deployment-info.txt <<EOF
Workshop Deployment Information
================================

Deployment Date: $(date)
Stack Prefix: $STACK_PREFIX
AWS Region: $AWS_REGION

Application URLs:
- Frontend: $APP_RUNNER_URL
- API Gateway: $API_GATEWAY_URL
- Cognito Login: $COGNITO_HOSTED_UI_URL

Authentication:
- User Pool ID: $COGNITO_USER_POOL_ID
- Client ID: $COGNITO_CLIENT_ID
- Test User: $TEST_USER_EMAIL
- Password: $TEST_USER_PASSWORD

Runtime Information:
- MCP Runtime ARN: $MCP_RUNTIME_ARN
- Agent Runtime ARN: $AGENT_RUNTIME_ARN

CloudFormation Stacks:
- ${STACK_PREFIX}-master (main infrastructure)
- ${STACK_PREFIX}-mcp-server (MCP Runtime)
- ${STACK_PREFIX}-coveo-agent (Agent Runtime)
- ${STACK_PREFIX}-ui-apprunner (UI Application)

Architecture:
UI → API Gateway → Lambda → Agent Runtime → MCP Runtime → Coveo API
EOF

print_status "Deployment information saved to deployment-info.txt" "INFO"
echo ""
print_status "🎉 Deployment completed successfully!" "SUCCESS"
