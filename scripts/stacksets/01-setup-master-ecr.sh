#!/bin/bash
#
# Setup ECR repositories in master account for cross-account access
#

set -e

STACK_PREFIX="workshop"
AWS_REGION="${AWS_REGION:-us-east-1}"
MASTER_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=========================================="
echo "Setting up Master Account ECR Repositories"
echo "=========================================="
echo "Master Account: $MASTER_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo ""

# Create MCP Server repository
echo "Creating MCP Server ECR repository..."
aws ecr create-repository \
  --repository-name "${STACK_PREFIX}-coveo-mcp-server-master" \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  --region "$AWS_REGION" 2>/dev/null || echo "Repository already exists"

# Create UI repository
echo "Creating UI ECR repository..."
aws ecr create-repository \
  --repository-name "${STACK_PREFIX}-ui-master" \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  --region "$AWS_REGION" 2>/dev/null || echo "Repository already exists"

# Set lifecycle policies
echo "Setting lifecycle policies..."
aws ecr put-lifecycle-policy \
  --repository-name "${STACK_PREFIX}-coveo-mcp-server-master" \
  --lifecycle-policy-text '{
    "rules": [{
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {"type": "expire"}
    }]
  }' \
  --region "$AWS_REGION" >/dev/null

aws ecr put-lifecycle-policy \
  --repository-name "${STACK_PREFIX}-ui-master" \
  --lifecycle-policy-text '{
    "rules": [{
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {"type": "expire"}
    }]
  }' \
  --region "$AWS_REGION" >/dev/null

echo ""
echo "✅ Master ECR repositories created successfully!"
echo ""
echo "MCP Server: ${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STACK_PREFIX}-coveo-mcp-server-master"
echo "UI: ${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STACK_PREFIX}-ui-master"
