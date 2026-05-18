#!/bin/bash
#
# Setup ECR repositories in master account for cross-account access
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
  log_error "Use credentials for the StackSets management/delegated admin account before deploying."
  exit 1
fi

echo "=========================================="
echo "Setting up Master Account ECR Repositories"
echo "=========================================="
echo "Master Account: $MASTER_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo ""

# Create Agent repository
echo "Creating Coveo Agent ECR repository..."
aws ecr create-repository \
  --repository-name "${STACK_PREFIX}-coveo-agent-master" \
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
  --repository-name "${STACK_PREFIX}-coveo-agent-master" \
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
echo "Coveo Agent: ${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STACK_PREFIX}-coveo-agent-master"
echo "UI: ${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STACK_PREFIX}-ui-master"
