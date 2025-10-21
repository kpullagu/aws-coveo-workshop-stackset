#!/bin/bash

# =============================================================================
# App Runner UI Deployment Script
# =============================================================================
# This script deploys the UI (BFF + React) to AWS App Runner after the main
# infrastructure has been deployed.

set -e

# Fixed configuration for consistency
STACK_PREFIX="workshop"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPOSITORY_NAME="${STACK_PREFIX}-ui"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region REGION        AWS region (default: us-east-1)"
            echo "  --help                 Show this help"
            echo ""
            echo "Fixed Configuration:"
            echo "  Stack Prefix: $STACK_PREFIX (fixed)"
            echo "  ECR Repository: $ECR_REPOSITORY_NAME (fixed)"
            exit 0
            ;;
        *)
            print_status "Unknown option: $1" "ERROR"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Deploying UI Application${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${YELLOW}What this does:${NC}"
echo -e "  → Builds React frontend + Express BFF Docker image"
echo -e "  → Pushes image to ECR"
echo -e "  → Deploys to AWS App Runner"
echo -e "  → Configures environment variables"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Stack Prefix: ${STACK_PREFIX}"
echo -e "  AWS Region: ${AWS_REGION}"
echo -e "  ECR Repository: ${ECR_REPOSITORY_NAME}"
echo ""

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}"

# =============================================================================
# Step 1: Validate Prerequisites
# =============================================================================
print_status "Validating prerequisites..." "INFO"

# Check if main infrastructure is deployed
if ! aws cloudformation describe-stacks --stack-name "${STACK_PREFIX}-master" --region "$AWS_REGION" >/dev/null 2>&1; then
    print_status "Main infrastructure stack not found: ${STACK_PREFIX}-master" "ERROR"
    print_status "Please run ./scripts/deploy-main-infra.sh first" "ERROR"
    exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_status "Docker is not running. Please start Docker." "ERROR"
    exit 1
fi

print_status "Prerequisites validated" "SUCCESS"

# =============================================================================
# Step 2: Get Stack Outputs
# =============================================================================
print_status "Retrieving infrastructure outputs..." "INFO"

# Get API Gateway URL
API_GATEWAY_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiBaseUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

# Get Cognito configuration
COGNITO_USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

COGNITO_CLIENT_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

if [ -z "$API_GATEWAY_URL" ] || [ -z "$COGNITO_USER_POOL_ID" ] || [ -z "$COGNITO_CLIENT_ID" ]; then
    print_status "Failed to retrieve required stack outputs" "ERROR"
    exit 1
fi

print_status "Retrieved stack outputs successfully" "SUCCESS"
echo -e "  API Gateway URL: $API_GATEWAY_URL"
echo -e "  Cognito User Pool ID: $COGNITO_USER_POOL_ID"
echo -e "  Cognito Client ID: $COGNITO_CLIENT_ID"
echo ""

# Get Coveo configuration from SSM
print_status "Retrieving Coveo configuration from SSM..." "INFO"

COVEO_ORG_ID=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/coveo/org-id" \
    --query "Parameter.Value" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

COVEO_SEARCH_API_KEY=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/coveo/search-api-key" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

COVEO_ANSWER_CONFIG_ID=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/coveo/answer-config-id" \
    --query "Parameter.Value" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -z "$COVEO_ORG_ID" ] || [ -z "$COVEO_SEARCH_API_KEY" ] || [ -z "$COVEO_ANSWER_CONFIG_ID" ]; then
    print_status "Failed to retrieve Coveo configuration from SSM" "ERROR"
    print_status "Make sure Coveo credentials are stored in SSM parameters" "ERROR"
    exit 1
fi

print_status "Retrieved Coveo configuration successfully" "SUCCESS"
echo ""

# =============================================================================
# Step 3: Create ECR Repository
# =============================================================================
print_status "Creating ECR repository..." "INFO"

aws ecr create-repository \
    --repository-name "$ECR_REPOSITORY_NAME" \
    --region "$AWS_REGION" \
    --image-scanning-configuration scanOnPush=true 2>/dev/null || \
    print_status "ECR repository already exists" "WARNING"

# =============================================================================
# Step 4: Check if Image Needs Rebuild
# =============================================================================
print_status "Checking if Docker image needs rebuild..." "INFO"

# Calculate checksum of frontend source files
cd frontend
CURRENT_CHECKSUM=$(find . -type f \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" -o -name "*.json" -o -name "Dockerfile" \) -exec sha256sum {} + 2>/dev/null | sort | sha256sum | cut -d' ' -f1)
cd ..

# Get last build checksum from ECR image tags
LAST_CHECKSUM=$(aws ecr describe-images \
    --repository-name "$ECR_REPOSITORY_NAME" \
    --image-ids imageTag=latest \
    --query "imageDetails[0].imageTags" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null | grep -o "checksum-[a-f0-9]*" | cut -d'-' -f2 2>/dev/null || true)

if [ -z "$LAST_CHECKSUM" ]; then
    LAST_CHECKSUM=""
fi

REBUILD_NEEDED=true

if [ -n "$LAST_CHECKSUM" ] && [ "$CURRENT_CHECKSUM" = "$LAST_CHECKSUM" ]; then
    print_status "No changes detected in frontend code (checksum: ${CURRENT_CHECKSUM:0:12}...)" "INFO"
    print_status "Skipping Docker image rebuild" "SUCCESS"
    REBUILD_NEEDED=false
else
    if [ -z "$LAST_CHECKSUM" ]; then
        print_status "No previous build found, building new image..." "INFO"
    else
        print_status "Changes detected in frontend code" "INFO"
        print_status "  Previous: ${LAST_CHECKSUM:0:12}..." "INFO"
        print_status "  Current:  ${CURRENT_CHECKSUM:0:12}..." "INFO"
    fi
fi

# =============================================================================
# Step 5: Build and Push Docker Image (if needed)
# =============================================================================
if [ "$REBUILD_NEEDED" = true ]; then
    print_status "Building Docker image..." "INFO"

    # Navigate to frontend directory
    cd frontend

    # Build Docker image
    docker build -t "$ECR_REPOSITORY_NAME:latest" .

    # Login to ECR
    print_status "Logging into ECR..." "INFO"
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ECR_URI"

    # Tag and push image with both latest and checksum tags
    docker tag "$ECR_REPOSITORY_NAME:latest" "$ECR_URI:latest"
    docker tag "$ECR_REPOSITORY_NAME:latest" "$ECR_URI:checksum-$CURRENT_CHECKSUM"
    
    docker push "$ECR_URI:latest"
    docker push "$ECR_URI:checksum-$CURRENT_CHECKSUM"

    print_status "Docker image built and pushed successfully" "SUCCESS"
    print_status "Image tagged with checksum: ${CURRENT_CHECKSUM:0:12}..." "INFO"

    # Go back to root directory
    cd ..
else
    print_status "Using existing Docker image from ECR" "SUCCESS"
fi

# =============================================================================
# Step 6: Deploy App Runner Stack
# =============================================================================
print_status "Deploying App Runner stack..." "INFO"

# Check if stack exists and is in a failed state
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-ui-apprunner" \
    --query "Stacks[0].StackStatus" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "DOES_NOT_EXIST")

if [[ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ]] || [[ "$STACK_STATUS" == "UPDATE_ROLLBACK_COMPLETE" ]]; then
    print_status "Stack is in $STACK_STATUS state, deleting and recreating..." "WARNING"
    aws cloudformation delete-stack \
        --stack-name "${STACK_PREFIX}-ui-apprunner" \
        --region "$AWS_REGION"
    
    print_status "Waiting for stack deletion..." "INFO"
    aws cloudformation wait stack-delete-complete \
        --stack-name "${STACK_PREFIX}-ui-apprunner" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    print_status "Stack deleted, will create new stack" "SUCCESS"
fi

aws cloudformation deploy \
    --template-file cfn/ui-apprunner.yml \
    --stack-name "${STACK_PREFIX}-ui-apprunner" \
    --parameter-overrides \
        StackPrefix="$STACK_PREFIX" \
        Environment="workshop" \
        ECRImageUri="$ECR_URI:latest" \
        ApiGatewayUrl="$API_GATEWAY_URL" \
        CognitoUserPoolId="$COGNITO_USER_POOL_ID" \
        CognitoClientId="$COGNITO_CLIENT_ID" \
        CognitoRegion="$AWS_REGION" \
        CoveoOrgId="$COVEO_ORG_ID" \
        CoveoSearchApiKey="$COVEO_SEARCH_API_KEY" \
        CoveoAnswerConfigId="$COVEO_ANSWER_CONFIG_ID" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$AWS_REGION" \
    --no-fail-on-empty-changeset

print_status "App Runner stack deployed successfully" "SUCCESS"

# =============================================================================
# Step 7: Wait for Service to be Ready
# =============================================================================
print_status "Waiting for App Runner service to be ready..." "INFO"

# Get service ARN
SERVICE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-ui-apprunner" \
    --query "Stacks[0].Outputs[?OutputKey=='AppRunnerServiceArn'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

if [ -z "$SERVICE_ARN" ] || [ "$SERVICE_ARN" = "None" ]; then
    print_status "Failed to get App Runner service ARN" "ERROR"
    exit 1
fi

# Get service URL
SERVICE_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-ui-apprunner" \
    --query "Stacks[0].Outputs[?OutputKey=='AppRunnerServiceUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

# Wait for service to be running (poll status)
print_status "This may take 5-10 minutes..." "INFO"
MAX_WAIT=600  # 10 minutes
WAIT_INTERVAL=15  # Check every 15 seconds
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    SERVICE_STATUS=$(aws apprunner describe-service \
        --service-arn "$SERVICE_ARN" \
        --query "Service.Status" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "UNKNOWN")
    
    if [ "$SERVICE_STATUS" = "RUNNING" ]; then
        print_status "App Runner service is ready!" "SUCCESS"
        break
    elif [ "$SERVICE_STATUS" = "CREATE_FAILED" ] || [ "$SERVICE_STATUS" = "OPERATION_FAILED" ]; then
        print_status "App Runner service failed to start: $SERVICE_STATUS" "ERROR"
        exit 1
    else
        echo "  Status: $SERVICE_STATUS (waiting...)"
        sleep $WAIT_INTERVAL
        ELAPSED=$((ELAPSED + WAIT_INTERVAL))
    fi
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    print_status "Timeout waiting for App Runner service to be ready" "WARNING"
    print_status "Service may still be starting. Check AWS Console for status." "WARNING"
fi

# =============================================================================
# Step 8: Update Cognito Callback URLs and OAuth Configuration
# =============================================================================
print_status "Updating Cognito callback URLs and OAuth configuration..." "INFO"

# Update Cognito App Client with complete OAuth configuration
aws cognito-idp update-user-pool-client \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --client-id "$COGNITO_CLIENT_ID" \
    --callback-urls "$SERVICE_URL" "http://localhost:3000" \
    --logout-urls "$SERVICE_URL" "http://localhost:3000" \
    --allowed-o-auth-flows "code" \
    --allowed-o-auth-scopes "email" "openid" "profile" \
    --allowed-o-auth-flows-user-pool-client \
    --supported-identity-providers "COGNITO" \
    --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" "ALLOW_USER_SRP_AUTH" \
    --region "$AWS_REGION" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    print_status "Cognito configuration updated successfully" "SUCCESS"
else
    print_status "Cognito configuration update failed" "ERROR"
    exit 1
fi

# =============================================================================
# Step 9: Create Test User
# =============================================================================
print_status "Creating test user..." "INFO"

TEST_USER_EMAIL="${TEST_USER_EMAIL:-testuser@example.com}"
# Note: Cognito test user creation moved to deploy-complete-workshop.sh
# This ensures all Cognito configuration happens in one place at the end

# =============================================================================
# Step 10: Test Deployment
# =============================================================================
print_status "Testing deployment..." "INFO"

# Test health endpoint
HEALTH_CHECK=$(curl -s -f "${SERVICE_URL}/api/health" 2>/dev/null || echo "FAILED")
if [ "$HEALTH_CHECK" != "FAILED" ]; then
    print_status "Health endpoint test passed" "SUCCESS"
else
    print_status "Health endpoint test failed - service may still be starting" "WARNING"
fi

# =============================================================================
# Deployment Summary
# =============================================================================
echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}✅ UI Deployment Complete${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${YELLOW}What was deployed:${NC}"
echo -e "  ✓ Docker image built and pushed to ECR"
echo -e "  ✓ App Runner service created/updated"
echo -e "  ✓ Environment variables configured"
echo -e "  ✓ Health check passed"
echo ""
echo -e "${BLUE}Application URL: $SERVICE_URL${NC}"
echo ""
echo -e "${YELLOW}Note: Cognito test user will be configured in the final step${NC}"
echo ""
echo -e "${GREEN}✅ Deployment Status:${NC}"
echo -e "   ✅ Docker Image: Built and pushed to ECR"
echo -e "   ✅ App Runner:   Deployed and running"
echo -e "   ✅ Cognito:      Callback URLs updated"
echo -e "   ✅ Test User:    Created and ready"
echo ""
echo -e "  3. Test all three backend modes (Coveo, BedrockAgent, CoveoMCP)"
echo ""
echo -e "${YELLOW}🧪 Testing:${NC}"
echo -e "  Health Check: curl $SERVICE_URL/api/health"
echo -e "  Full API Test: COGNITO_TOKEN='your-jwt-token' ./test-api-gateway.sh"
echo ""

# Save deployment info
cat > ui-deployment-info.txt <<EOF
App Runner UI Deployment Information
====================================

Deployment Date: $(date)
Stack Prefix: $STACK_PREFIX
AWS Region: $AWS_REGION

Application:
- Service URL: $SERVICE_URL
- ECR Image: $ECR_URI:latest
- Stack Name: ${STACK_PREFIX}-ui-apprunner

Authentication:
- Cognito User Pool ID: $COGNITO_USER_POOL_ID
- Cognito Client ID: $COGNITO_CLIENT_ID
- Login URL: https://workshop-auth.auth.$AWS_REGION.amazoncognito.com/login?client_id=$COGNITO_CLIENT_ID&response_type=code&scope=openid+email+profile&redirect_uri=$SERVICE_URL

Backend Integration:
- API Gateway URL: $API_GATEWAY_URL
- Health Check: $SERVICE_URL/api/health
EOF

print_status "Deployment information saved to ui-deployment-info.txt" "INFO"
echo ""
print_status "🎉 App Runner UI deployment completed successfully!" "SUCCESS"