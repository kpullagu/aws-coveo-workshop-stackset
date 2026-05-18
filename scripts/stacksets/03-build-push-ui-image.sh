#!/bin/bash
#
# Build and push UI Docker image to master ECR
#

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Ensure we're in the project root
cd "$SCRIPT_DIR/../.."

ACTIVE_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION")
if [ "$ACTIVE_ACCOUNT_ID" != "$MASTER_ACCOUNT_ID" ]; then
  log_error "Active AWS account ($ACTIVE_ACCOUNT_ID) does not match MASTER_ACCOUNT_ID ($MASTER_ACCOUNT_ID)"
  log_error "Use credentials for the StackSets management/delegated admin account before building/pushing images."
  exit 1
fi

ECR_REPO="${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STACK_PREFIX}-ui-master"

echo "=========================================="
echo "Building and Pushing UI Image"
echo "=========================================="
echo "ECR Repository: $ECR_REPO"
echo "Image Tag: ${UI_IMAGE_TAG}"
echo ""

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Build image
echo "Building UI Docker image..."
cd frontend
docker build --platform linux/amd64 -t "${STACK_PREFIX}-ui:${UI_IMAGE_TAG}" .
cd ..

# Tag image
echo "Tagging image..."
docker tag "${STACK_PREFIX}-ui:${UI_IMAGE_TAG}" "${ECR_REPO}:${UI_IMAGE_TAG}"
docker tag "${STACK_PREFIX}-ui:${UI_IMAGE_TAG}" "${ECR_REPO}:latest"

# Push image
echo "Pushing image to ECR..."
docker push "${ECR_REPO}:${UI_IMAGE_TAG}"
docker push "${ECR_REPO}:latest"

echo ""
echo "✅ UI image pushed successfully!"
echo "Image URI: ${ECR_REPO}:${UI_IMAGE_TAG}"
