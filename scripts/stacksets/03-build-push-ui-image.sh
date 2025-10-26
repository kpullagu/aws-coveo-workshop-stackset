#!/bin/bash
#
# Build and push UI Docker image to master ECR
#

set -e

STACK_PREFIX="workshop"
AWS_REGION="${AWS_REGION:-us-east-1}"
MASTER_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STACK_PREFIX}-ui-master"

echo "=========================================="
echo "Building and Pushing UI Image"
echo "=========================================="
echo "ECR Repository: $ECR_REPO"
echo ""

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Build image
echo "Building UI Docker image..."
cd frontend
docker build --platform linux/amd64 -t "${STACK_PREFIX}-ui:latest" .
cd ..

# Tag image
echo "Tagging image..."
docker tag "${STACK_PREFIX}-ui:latest" "${ECR_REPO}:latest"

# Push image
echo "Pushing image to ECR..."
docker push "${ECR_REPO}:latest"

echo ""
echo "✅ UI image pushed successfully!"
echo "Image URI: ${ECR_REPO}:latest"
