#!/bin/bash
#
# Build and push MCP Server Docker image to master ECR
#

set -e

STACK_PREFIX="workshop"
AWS_REGION="${AWS_REGION:-us-east-1}"
MASTER_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STACK_PREFIX}-coveo-mcp-server-master"

echo "=========================================="
echo "Building and Pushing MCP Server Image"
echo "=========================================="
echo "ECR Repository: $ECR_REPO"
echo ""

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Build image for ARM64 (required by Bedrock AgentCore)
echo "Building MCP Server Docker image for ARM64..."
cd coveo-mcp-server
docker build --platform linux/arm64 -t "${STACK_PREFIX}-mcp-server:latest" .
cd ..

# Tag image
echo "Tagging image..."
docker tag "${STACK_PREFIX}-mcp-server:latest" "${ECR_REPO}:latest"

# Push image
echo "Pushing image to ECR..."
docker push "${ECR_REPO}:latest"

echo ""
echo "✅ MCP Server image pushed successfully!"
echo "Image URI: ${ECR_REPO}:latest"
