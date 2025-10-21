#!/bin/bash

# =============================================================================
# Show Deployment Information
# =============================================================================
# Displays all deployment information including URLs and credentials
# =============================================================================

set -e

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

STACK_PREFIX="${STACK_PREFIX:-workshop}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Workshop Deployment Information${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Get CloudFormation outputs
echo -e "${YELLOW}📦 CloudFormation Stacks:${NC}"

MASTER_STACK="${STACK_PREFIX}-master"
UI_STACK="${STACK_PREFIX}-ui-apprunner"
MCP_STACK="${STACK_PREFIX}-mcp-server"
AGENT_STACK="${STACK_PREFIX}-coveo-agent"

for stack in "$MASTER_STACK" "$UI_STACK" "$MCP_STACK" "$AGENT_STACK"; do
    STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$stack" \
        --region "$AWS_REGION" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$STATUS" = "NOT_FOUND" ]; then
        echo "  ❌ $stack: Not deployed"
    elif [ "$STATUS" = "CREATE_COMPLETE" ] || [ "$STATUS" = "UPDATE_COMPLETE" ]; then
        echo -e "  ${GREEN}✓${NC} $stack: $STATUS"
    else
        echo -e "  ${YELLOW}⚠${NC} $stack: $STATUS"
    fi
done

# Get URLs
echo ""
echo -e "${YELLOW}🌐 Application URLs:${NC}"

APP_RUNNER_URL=$(aws cloudformation describe-stacks \
    --stack-name "$UI_STACK" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AppRunnerServiceUrl'].OutputValue" \
    --output text 2>/dev/null || echo "Not available")

API_GATEWAY_URL=$(aws cloudformation describe-stacks \
    --stack-name "$MASTER_STACK" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiBaseUrl'].OutputValue" \
    --output text 2>/dev/null || echo "Not available")

COGNITO_HOSTED_UI_URL=$(aws cloudformation describe-stacks \
    --stack-name "$MASTER_STACK" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='CognitoHostedUIUrl'].OutputValue" \
    --output text 2>/dev/null || echo "Not available")

echo "  Frontend: $APP_RUNNER_URL"
echo "  API Gateway: $API_GATEWAY_URL"
echo "  Cognito Login: $COGNITO_HOSTED_UI_URL"

# Get Cognito info
echo ""
echo -e "${YELLOW}🔐 Cognito Configuration:${NC}"

USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name "$MASTER_STACK" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text 2>/dev/null || echo "Not available")

CLIENT_ID=$(aws cloudformation describe-stacks \
    --stack-name "$MASTER_STACK" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" \
    --output text 2>/dev/null || echo "Not available")

echo "  User Pool ID: $USER_POOL_ID"
echo "  Client ID: $CLIENT_ID"

# Get callback URLs
if [ "$USER_POOL_ID" != "Not available" ] && [ "$CLIENT_ID" != "Not available" ]; then
    echo ""
    echo -e "${YELLOW}🔗 Cognito Callback URLs:${NC}"
    
    CALLBACK_URLS=$(aws cognito-idp describe-user-pool-client \
        --user-pool-id "$USER_POOL_ID" \
        --client-id "$CLIENT_ID" \
        --region "$AWS_REGION" \
        --query 'UserPoolClient.CallbackURLs' \
        --output json 2>/dev/null || echo "[]")
    
    echo "$CALLBACK_URLS" | jq -r '.[]' | while read url; do
        echo "  - $url"
    done
fi

# List Cognito users
echo ""
echo -e "${YELLOW}👤 Cognito Users:${NC}"

if [ "$USER_POOL_ID" != "Not available" ]; then
    USERS=$(aws cognito-idp list-users \
        --user-pool-id "$USER_POOL_ID" \
        --region "$AWS_REGION" \
        --query 'Users[].{Username:Username,Email:Attributes[?Name==`email`].Value|[0],Status:UserStatus}' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$(echo "$USERS" | jq '. | length')" -gt 0 ]; then
        echo "$USERS" | jq -r '.[] | "  - \(.Email) (\(.Username)) - Status: \(.Status)"'
    else
        echo "  No users found"
    fi
fi

# Show credentials from .env
echo ""
echo -e "${YELLOW}🔑 Test Credentials (from .env):${NC}"
echo "  Email: ${TEST_USER_EMAIL:-testuser@example.com (default)}"
echo "  Password: ${TEST_USER_PASSWORD:-TempPassword123! (default)}"

# Get AgentCore Runtimes
echo ""
echo -e "${YELLOW}🤖 AgentCore Runtimes:${NC}"

MCP_RUNTIME_ARN=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/coveo/mcp-runtime-arn" \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "Not available")

AGENT_RUNTIME_ARN=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/coveo/agent-runtime-arn" \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "Not available")

echo "  MCP Runtime ARN: $MCP_RUNTIME_ARN"
echo "  Agent Runtime ARN: $AGENT_RUNTIME_ARN"

# Summary
echo ""
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${GREEN}📝 Quick Start${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""
echo "1. Open your browser to:"
echo "   $APP_RUNNER_URL"
echo ""
echo "2. Click 'Login' and use:"
echo "   Email: ${TEST_USER_EMAIL:-testuser@example.com}"
echo "   Password: ${TEST_USER_PASSWORD:-TempPassword123!}"
echo ""
echo "3. Test all three backend modes:"
echo "   - Coveo (direct API)"
echo "   - BedrockAgent (with Bedrock Agent)"
echo "   - coveoMCP (with MCP Server)"
echo ""

# Check if credentials match actual user
if [ "$USER_POOL_ID" != "Not available" ]; then
    ACTUAL_USER=$(aws cognito-idp list-users \
        --user-pool-id "$USER_POOL_ID" \
        --region "$AWS_REGION" \
        --query 'Users[0].Attributes[?Name==`email`].Value|[0]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ACTUAL_USER" ] && [ "$ACTUAL_USER" != "${TEST_USER_EMAIL:-testuser@example.com}" ]; then
        echo -e "${YELLOW}⚠️  WARNING: The actual Cognito user email ($ACTUAL_USER) doesn't match your .env file!${NC}"
        echo ""
        echo "The actual user in Cognito is: $ACTUAL_USER"
        echo "Your .env file has: ${TEST_USER_EMAIL:-testuser@example.com}"
        echo ""
        echo "To fix this, either:"
        echo "1. Update your .env file with: TEST_USER_EMAIL=$ACTUAL_USER"
        echo "2. Or create a new user with your .env credentials"
        echo ""
    fi
fi
