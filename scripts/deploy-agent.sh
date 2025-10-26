#!/bin/bash

# =============================================================================
# Deploy Coveo Agent (Orchestrator)
# =============================================================================
# Builds Agent Docker image locally and deploys to AgentCore Runtime
# Agent orchestrates MCP tool calls with Bedrock for answer synthesis
# =============================================================================

set -e

STACK_PREFIX="${STACK_PREFIX:-workshop}"
REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_PREFIX}-coveo-agent"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Deploying Coveo Agent (Orchestrator)${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${YELLOW}What this does:${NC}"
echo -e "  → Builds Agent Docker image locally"
echo -e "  → Pushes image to ECR"
echo -e "  → Creates AgentCore Runtime for Agent"
echo -e "  → Configures Agent to call MCP Runtime"
echo ""

# Read required parameters from SSM
echo "Reading configuration from SSM..."

# Get MCP runtime ARN
MCP_RUNTIME_ARN=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/coveo/mcp-runtime-arn" \
    --query 'Parameter.Value' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [ -z "$MCP_RUNTIME_ARN" ]; then
    echo "❌ MCP runtime ARN not found. Deploy MCP server first."
    echo "   Run: bash scripts/deploy-mcp.sh"
    exit 1
fi

# Get or set default model ID
MODEL_ID=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/coveo/bedrock-model-id" \
    --query 'Parameter.Value' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

# Set default model if not found or empty
if [ -z "$MODEL_ID" ] || [[ "$MODEL_ID" == *"ParameterNotFound"* ]]; then
    MODEL_ID="us.amazon.nova-lite-v1:0"  # Amazon Nova Lite inference profile
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/bedrock-model-id" \
        --value "$MODEL_ID" \
        --type String \
        --overwrite \
        --region "$REGION" > /dev/null
    echo "✓ Set default Bedrock Model ID"
fi

echo "✓ MCP Runtime ARN: $MCP_RUNTIME_ARN"
echo "✓ Bedrock Model ID: $MODEL_ID"
echo "✓ AWS Region: $REGION"
echo ""

# Step 1: Create ECR repository if it doesn't exist
echo "Step 1: Setting up ECR repository..."
ECR_REPO_NAME="${STACK_PREFIX}-coveo-agent"

# Check if ECR repository exists
if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$REGION" &> /dev/null; then
    echo "✓ ECR repository already exists"
else
    echo "Creating ECR repository..."
    aws ecr create-repository \
        --repository-name "$ECR_REPO_NAME" \
        --region "$REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 > /dev/null
    echo "✓ ECR repository created"
fi

# Get ECR repository URI
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"
echo "✓ ECR Repository: $ECR_REPO"
echo ""

# Step 2: Build and push Docker image
echo "Step 2: Building and pushing Agent Docker image..."

echo "✓ ECR Repository: $ECR_REPO"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR_REPO" > /dev/null 2>&1

echo "✓ Logged in to ECR"

# Build and push Agent image
echo "Building Agent image for ARM64..."
cd coveo-agent

# Use buildx for ARM64 build
docker buildx build \
    --platform linux/arm64 \
    --build-arg AWS_REGION="$REGION" \
    --build-arg BEDROCK_MODEL_ID="$MODEL_ID" \
    --build-arg COVEO_MCP_RUNTIME_ARN="$MCP_RUNTIME_ARN" \
    -t "$ECR_REPO:latest" \
    --push \
    .

if [ $? -ne 0 ]; then
    echo "❌ Docker build failed"
    cd ..
    exit 1
fi

echo "✓ Agent image built and pushed"

cd ..
echo ""

# Step 3: Create or update CloudFormation stack
echo "Step 3: Deploying Agent CloudFormation stack..."

# Check if stack exists
STACK_EXISTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$STACK_EXISTS" = "NOT_FOUND" ]; then
    echo "Creating new Agent stack..."
    
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body file://coveo-agent/agent-template.yaml \
        --parameters \
            ParameterKey=StackPrefix,ParameterValue="$STACK_PREFIX" \
            ParameterKey=BedrockModelId,ParameterValue="$MODEL_ID" \
            ParameterKey=MCPRuntimeArn,ParameterValue="$MCP_RUNTIME_ARN" \
            ParameterKey=AWSRegion,ParameterValue="$REGION" \
            ParameterKey=ImageTag,ParameterValue="latest" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" > /dev/null
    
    echo "✓ Stack creation initiated"
    echo "Waiting for stack creation to complete (this may take 3-5 minutes)..."
    
    aws cloudformation wait stack-create-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
    
    echo "✓ Stack created successfully"
else
    echo "Stack exists, updating..."
    
    aws cloudformation update-stack \
        --stack-name "$STACK_NAME" \
        --template-body file://coveo-agent/agent-template.yaml \
        --parameters \
            ParameterKey=StackPrefix,ParameterValue="$STACK_PREFIX" \
            ParameterKey=BedrockModelId,ParameterValue="$MODEL_ID" \
            ParameterKey=MCPRuntimeArn,ParameterValue="$MCP_RUNTIME_ARN" \
            ParameterKey=AWSRegion,ParameterValue="$REGION" \
            ParameterKey=ImageTag,ParameterValue="latest" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✓ Stack update initiated"
        echo "Waiting for stack update to complete..."
        
        aws cloudformation wait stack-update-complete \
            --stack-name "$STACK_NAME" \
            --region "$REGION" 2>/dev/null
        
        echo "✓ Stack updated successfully"
    else
        echo "✓ No stack changes needed"
    fi
fi
echo ""

# Step 4: Configure X-Ray trace segment destination for Transaction Search
echo "Step 4: Configuring X-Ray for Transaction Search..."
echo "Enabling CloudWatch Logs as trace segment destination..."

# Temporarily disable exit-on-error for this optional step
set +e
aws xray update-trace-segment-destination \
    --destination CloudWatchLogs \
    --region "$REGION" > /dev/null 2>&1
XRAY_EXIT_CODE=$?
set -e

if [ $XRAY_EXIT_CODE -eq 0 ]; then
    echo "✓ X-Ray configured to use CloudWatch Logs for traces"
    echo "✓ Transaction Search enabled (OTLP API support)"
else
    echo "⚠️  X-Ray configuration may have failed (might already be configured)"
fi
echo ""

# Get Agent runtime ARN from CloudFormation outputs
echo "Getting Agent runtime ARN..."
AGENT_RUNTIME_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`AgentRuntimeArn`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -z "$AGENT_RUNTIME_ARN" ]; then
    echo "❌ Agent runtime ARN not found in stack outputs"
    exit 1
fi

AGENT_RUNTIME_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`AgentRuntimeId`].OutputValue' \
    --output text 2>/dev/null || echo "")

echo "✓ Agent Runtime ARN: $AGENT_RUNTIME_ARN"
echo "✓ Agent Runtime ID: $AGENT_RUNTIME_ID"

# Write Agent runtime configuration to SSM
echo "Writing Agent runtime configuration to SSM..."
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/coveo/agent-runtime-arn" \
    --value "$AGENT_RUNTIME_ARN" \
    --type String \
    --overwrite \
    --region "$REGION" > /dev/null

# Save as primary runtime ARN for Lambda consumption
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/coveo/runtime-arn" \
    --value "$AGENT_RUNTIME_ARN" \
    --type String \
    --overwrite \
    --region "$REGION" > /dev/null

# Save runtime ID
if [ -n "$AGENT_RUNTIME_ID" ]; then
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/runtime-id" \
        --value "$AGENT_RUNTIME_ID" \
        --type String \
        --overwrite \
        --region "$REGION" > /dev/null
fi

echo "✓ Agent runtime ARN saved to SSM: /${STACK_PREFIX}/coveo/agent-runtime-arn"
echo "✓ Runtime ARN saved for Lambda: /${STACK_PREFIX}/coveo/runtime-arn"

echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}✅ Agent Deployment Complete${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${YELLOW}What was deployed:${NC}"
echo -e "  ✓ Agent Docker image built and pushed"
echo -e "  ✓ AgentCore Runtime for Agent created"
echo -e "  ✓ Agent configured to call MCP Runtime"
echo -e "  ✓ Runtime ARN saved to SSM"
echo ""
echo -e "${BLUE}Agent Runtime ARN: $AGENT_RUNTIME_ARN${NC}"
echo -e "${BLUE}Agent Runtime ID: $AGENT_RUNTIME_ID${NC}"
echo -e "${BLUE}MCP Runtime ARN: $MCP_RUNTIME_ARN${NC}"
echo -e "${BLUE}Bedrock Model: $MODEL_ID${NC}"
echo ""
echo -e "${YELLOW}Architecture:${NC}"
echo -e "  Lambda → Agent Runtime → MCP Runtime → Coveo API"
echo ""
