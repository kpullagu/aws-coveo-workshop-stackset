#!/bin/bash
#
# Build and push Coveo Agent Docker image to master ECR
#

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Ensure we're in the project root
cd "$SCRIPT_DIR/../.."

log_info "=========================================="
log_info "Building and Pushing Coveo Agent Image"
log_info "=========================================="
log_info "ECR Repository: ${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STACK_PREFIX}-coveo-agent-master"
echo ""

# Create ECR repository if it doesn't exist
AGENT_REPO_NAME="${STACK_PREFIX}-coveo-agent-master"
log_info "Checking ECR repository: $AGENT_REPO_NAME"

if ! aws ecr describe-repositories --repository-names "$AGENT_REPO_NAME" --region "$AWS_REGION" 2>/dev/null; then
    log_info "Creating ECR repository..."
    aws ecr create-repository \
        --repository-name "$AGENT_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --region "$AWS_REGION" >/dev/null
    
    # Set lifecycle policy
    aws ecr put-lifecycle-policy \
        --repository-name "$AGENT_REPO_NAME" \
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
    
    log_success "ECR repository created"
else
    log_info "ECR repository already exists"
fi

# Login to ECR
log_info "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" >/dev/null

log_success "Logged in to ECR"

# Build Coveo Agent image
log_info "Building Coveo Agent Docker image..."
cd coveo-agent

# Build for ARM64 (AgentCore Runtime uses ARM64)
docker buildx build \
    --platform linux/arm64 \
    --build-arg AWS_REGION="$AWS_REGION" \
    --build-arg BEDROCK_MODEL_ID="$BEDROCK_MODEL" \
    -t "${STACK_PREFIX}-coveo-agent:latest" \
    --load \
    .

if [ $? -ne 0 ]; then
    log_error "Docker build failed"
    cd ..
    exit 1
fi

log_success "Coveo Agent image built"

# Tag image
ECR_REPO="${MASTER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${AGENT_REPO_NAME}"
log_info "Tagging image..."
docker tag "${STACK_PREFIX}-coveo-agent:latest" "${ECR_REPO}:latest"

# Push image
log_info "Pushing image to ECR..."
docker push "${ECR_REPO}:latest"

cd ..

echo ""
log_success "Coveo Agent image pushed successfully!"
echo "Image URI: ${ECR_REPO}:latest"
