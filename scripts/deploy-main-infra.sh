#!/bin/bash
#
# Deploy script for Coveo + AWS Workshop
# 
# Usage:
#   ./scripts/deploy-main-infra.sh [--region REGION] [--help]
#
# Prerequisites:
#   - AWS CLI v2 configured with credentials
#   - Bash shell (Git Bash on Windows, native on macOS/Linux)
#   - Python 3.12+ for Lambda packaging
#   - Environment variables or config/.env file with Coveo credentials
#

set -e  # Exit on error
set -o pipefail  # Propagate pipe failures

# Fixed values - no longer configurable to ensure consistency
STACK_PREFIX="workshop"
AWS_REGION="${AWS_REGION:-us-east-1}"
DEPLOY_BEDROCK="true"
# Note: AgentCore Runtimes (MCP + Agent) are deployed separately via deploy-mcp.sh and deploy-agent.sh

# Get AWS Account ID for unique bucket names
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Fixed S3 bucket names for consistency (must be globally unique)
CFN_BUCKET_NAME="workshop-${AWS_ACCOUNT_ID}-cfn-templates"
UI_BUCKET_NAME="workshop-${AWS_ACCOUNT_ID}-ui"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --no-bedrock)
            DEPLOY_BEDROCK="false"
            shift
            ;;

        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region REGION        AWS region (default: us-east-1)"
            echo "  --no-bedrock           Skip Bedrock Agent deployment (Lab 2)"
            echo "  --help                 Show this help message"
            echo ""
            echo "Fixed Configuration:"
            echo "  Stack Prefix:          workshop (fixed)"
            echo "  CFN S3 Bucket:         workshop-{ACCOUNT_ID}-cfn-templates (dynamic)"
            echo "  UI S3 Bucket:          workshop-{ACCOUNT_ID}-ui (dynamic)"
            echo ""
            echo "Environment Variables:"
            echo "  COVEO_ORG_ID          Coveo organization ID (required)"
            echo "  AWS_PROFILE           AWS CLI profile to use (optional)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

# Load environment variables from .env files if they exist
if [ -f ".env" ]; then
    log_info "Loading environment variables from .env"
    set -a
    source .env
    set +a
elif [ -f "config/.env" ]; then
    log_info "Loading environment variables from config/.env"
    set -a
    source config/.env
    set +a
fi

# Validate required environment variables
REQUIRED_VARS=("COVEO_ORG_ID" "COVEO_SEARCH_API_KEY" "COVEO_ANSWER_CONFIG_ID")
MISSING_VARS=()

for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        MISSING_VARS+=("$VAR")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    log_error "Missing required environment variables: ${MISSING_VARS[*]}"
    log_info "Please set these variables in your .env file or environment"
    log_info "Required variables:"
    for VAR in "${MISSING_VARS[@]}"; do
        echo "  - $VAR"
    done
    exit 1
fi

log_success "All required environment variables are set"

# Note: This script is called by deploy-complete-workshop.sh
# No interactive prompts or duplicate messages

echo ""
log_info "=========================================="
log_info "Preparing S3 Buckets"
log_info "=========================================="
log_info "Setting up CloudFormation templates and UI asset buckets..."

# Create CFN bucket if it doesn't exist (this is needed before CloudFormation deployment)
log_info "Setting up CloudFormation templates bucket: $CFN_BUCKET_NAME"
if aws s3 ls "s3://${CFN_BUCKET_NAME}" --region "$AWS_REGION" 2>/dev/null; then
    log_info "CFN bucket exists, clearing contents for fresh deployment..."
    aws s3 rm "s3://${CFN_BUCKET_NAME}" --recursive --region "$AWS_REGION" 2>/dev/null || true
else
    log_info "Creating new CFN bucket: $CFN_BUCKET_NAME"
    aws s3 mb "s3://${CFN_BUCKET_NAME}" --region "$AWS_REGION" 2>/dev/null || {
        log_error "Failed to create CFN bucket. It may exist in another region or account."
        exit 1
    }
fi

# Enable versioning on CFN bucket
aws s3api put-bucket-versioning \
    --bucket "$CFN_BUCKET_NAME" \
    --versioning-configuration Status=Enabled \
    --region "$AWS_REGION"

# Check if UI bucket exists and handle it
log_info "Checking UI bucket: $UI_BUCKET_NAME"
if aws s3 ls "s3://${UI_BUCKET_NAME}" --region "$AWS_REGION" 2>/dev/null; then
    log_warning "UI bucket already exists. CloudFormation will fail if it tries to create it."
    log_info "Checking if bucket is managed by CloudFormation..."
    
    # Check if the bucket is part of an existing CloudFormation stack
    EXISTING_STACK=$(aws cloudformation describe-stack-resources \
        --physical-resource-id "$UI_BUCKET_NAME" \
        --query 'StackResources[0].StackName' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [ "$EXISTING_STACK" != "None" ] && [ -n "$EXISTING_STACK" ]; then
        log_info "Bucket is managed by CloudFormation stack: $EXISTING_STACK"
        log_info "CloudFormation will update the existing bucket"
    else
        log_warning "Bucket exists but is not managed by CloudFormation"
        log_info "You have two options:"
        echo "  1. Delete the bucket manually: aws s3 rb s3://$UI_BUCKET_NAME --force --region $AWS_REGION"
        echo "  2. Continue and let CloudFormation fail, then use the existing bucket"
        echo ""
        read -p "Do you want to delete the existing bucket and let CloudFormation recreate it? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting existing UI bucket..."
            aws s3 rm "s3://${UI_BUCKET_NAME}" --recursive --region "$AWS_REGION" 2>/dev/null || true
            aws s3 rb "s3://${UI_BUCKET_NAME}" --region "$AWS_REGION" 2>/dev/null || true
            log_success "Existing UI bucket deleted"
        else
            log_warning "Continuing with existing bucket. CloudFormation may fail."
        fi
    fi
else
    log_info "UI bucket does not exist. CloudFormation will create it."
fi

log_success "S3 bucket preparation completed"

echo ""
log_info "=========================================="
log_info "Packaging Lambda Functions"
log_info "=========================================="
log_info "Creating deployment packages for all Lambda functions..."

# Create/Update Lambda Layer with shared dependencies
log_info "Creating Lambda Layer with shared dependencies..."
if [ -f "scripts/create-lambda-layer.sh" ]; then
    bash scripts/create-lambda-layer.sh "$AWS_REGION"
    if [ $? -ne 0 ]; then
        log_warning "Lambda Layer creation failed, will use full packaging"
    else
        log_success "Lambda Layer created"
    fi
fi

# Check which packaging script is available
if [ -f "scripts/package-lambdas.sh" ]; then
    log_info "Running automated Lambda packaging script..."
    bash scripts/package-lambdas.sh "$CFN_BUCKET_NAME" "$AWS_REGION"
    
    if [ $? -ne 0 ]; then
        log_error "Lambda packaging failed"
        exit 1
    fi
    
    log_success "All Lambda functions packaged and uploaded to S3"
elif [ -f "scripts/package-lambdas.ps1" ]; then
    log_info "Running PowerShell Lambda packaging script..."
    powershell -File scripts/package-lambdas.ps1 -BucketName "$CFN_BUCKET_NAME" -Region "$AWS_REGION"
    
    if [ $? -ne 0 ]; then
        log_error "Lambda packaging failed"
        exit 1
    fi
    
    log_success "All Lambda functions packaged and uploaded to S3"
else
    # Fallback to manual packaging if scripts not found
    log_warning "Automated packaging scripts not found, using manual packaging..."
    
    LAMBDA_DIRS=(
        "lambdas/search_proxy"
        "lambdas/passages_proxy"
        "lambdas/answering_proxy"
        "lambdas/query_suggest_proxy"
        "lambdas/html_proxy"
        "lambdas/coveo_passage_tool_py"
        "lambdas/agentcore_runtime_py"
        "lambdas/bedrock_agent_chat"
    )

    for LAMBDA_DIR in "${LAMBDA_DIRS[@]}"; do
        if [ ! -d "$LAMBDA_DIR" ]; then
            log_warning "Lambda directory not found: $LAMBDA_DIR, skipping..."
            continue
        fi
        
        LAMBDA_NAME=$(basename "$LAMBDA_DIR")
        log_info "Packaging $LAMBDA_NAME..."
        
        # Create package directory
        mkdir -p "$LAMBDA_DIR/package"
        
        # Install dependencies (if requirements.txt exists and has content)
        if [ -s "$LAMBDA_DIR/requirements.txt" ]; then
            pip install -r "$LAMBDA_DIR/requirements.txt" -t "$LAMBDA_DIR/package" --quiet --upgrade
        fi
        
        # Copy config module to package
        if [ -d "config" ]; then
            cp -r config "$LAMBDA_DIR/package/"
        fi
        
        # Create ZIP file
        cd "$LAMBDA_DIR/package"
        zip -r "../${LAMBDA_NAME}.zip" . -q
        cd ..
        zip -g "${LAMBDA_NAME}.zip" lambda_function.py -q
        cd ../..
        
        # Upload to S3
        aws s3 cp "$LAMBDA_DIR/${LAMBDA_NAME}.zip" "s3://${CFN_BUCKET_NAME}/lambdas/${LAMBDA_NAME}.zip" --region "$AWS_REGION"
        
        log_success "Packaged and uploaded $LAMBDA_NAME"
        
        # Clean up
        rm -rf "$LAMBDA_DIR/package"
    done
fi

echo ""
log_success "Lambda packaging complete!"
echo ""

echo ""
log_info "=========================================="
log_info "Uploading CloudFormation Templates"
log_info "=========================================="
log_info "Syncing templates to S3 bucket..."
aws s3 sync cfn/ "s3://${CFN_BUCKET_NAME}/cfn/" --region "$AWS_REGION" --delete

log_success "Uploaded CloudFormation templates to s3://${CFN_BUCKET_NAME}/cfn/"
echo ""

# Note: MCP Server deployment is now handled separately by deploy-complete-workshop.sh
# which calls scripts/deploy-mcp.sh with integrated CodeBuild in the MCP template

echo ""
log_info "=========================================="
log_info "Deploying CloudFormation Stack"
log_info "=========================================="
log_info "Creating/updating master stack with nested stacks..."
log_info "This includes: Auth (Cognito), Core (API Gateway, Lambda), Bedrock Agent"

# Get Lambda Layer ARN if it exists
LAMBDA_LAYER_ARN=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/lambda-layer-arn" \
    --query "Parameter.Value" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$LAMBDA_LAYER_ARN" ]; then
    log_info "Using Lambda Layer: $LAMBDA_LAYER_ARN"
    LAYER_PARAM="LambdaLayerArn=$LAMBDA_LAYER_ARN"
else
    log_info "No Lambda Layer found, Lambdas will include dependencies"
    LAYER_PARAM="LambdaLayerArn="
fi

# IMPORTANT: Create SSM parameters BEFORE CloudFormation deployment
# CloudFormation uses {{resolve:ssm:...}} which requires parameters to exist
log_info "Creating SSM parameters before CloudFormation deployment..."

# Store Coveo Org ID in SSM Parameter Store
log_info "Storing Coveo Org ID in SSM Parameter Store..."
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/coveo/org-id" \
    --value "$COVEO_ORG_ID" \
    --type "String" \
    --overwrite \
    --description "Coveo organization ID" \
    --region "$AWS_REGION" >/dev/null 2>&1

log_success "Stored: /${STACK_PREFIX}/coveo/org-id"

# Store Coveo Answer Config ID in SSM
log_info "Storing Coveo Answer Config ID in SSM..."
if [ -n "$COVEO_ANSWER_CONFIG_ID" ] && [ "$COVEO_ANSWER_CONFIG_ID" != "NOT_CONFIGURED" ]; then
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/answer-config-id" \
        --value "$COVEO_ANSWER_CONFIG_ID" \
        --type "String" \
        --overwrite \
        --description "Coveo Answer API configuration ID" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    log_success "Stored: /${STACK_PREFIX}/coveo/answer-config-id"
else
    log_warning "COVEO_ANSWER_CONFIG_ID is empty or not configured, skipping SSM parameter creation"
fi

# Store Coveo Search API Key in SSM Parameter Store as plain String
log_info "Storing Coveo Search API Key in SSM Parameter Store (String)..."
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/coveo/search-api-key" \
    --value "$COVEO_SEARCH_API_KEY" \
    --type "String" \
    --overwrite \
    --region "$AWS_REGION" >/dev/null 2>&1

log_success "Stored: /${STACK_PREFIX}/coveo/search-api-key (SSM String)"

log_success "All SSM parameters created successfully!"
echo ""

aws cloudformation deploy \
    --template-file cfn/master.yml \
    --stack-name "${STACK_PREFIX}-master" \
    --parameter-overrides \
        StackPrefix="$STACK_PREFIX" \
        S3BucketName="$UI_BUCKET_NAME" \
        CfnTemplateBucket="$CFN_BUCKET_NAME" \
        CognitoDomainPrefix="${STACK_PREFIX}-auth" \
        CoveoOrgId="$COVEO_ORG_ID" \
        CoveoAnswerConfigId="$COVEO_ANSWER_CONFIG_ID" \
        DeployBedrockAgent="$DEPLOY_BEDROCK" \
        Environment="workshop" \
        $LAYER_PARAM \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_NAMED_IAM \
    --region "$AWS_REGION" \
    --no-fail-on-empty-changeset

# Wait for stack creation/update to complete
log_info "Waiting for CloudFormation stack to complete..."
aws cloudformation wait stack-create-complete \
    --stack-name "${STACK_PREFIX}-master" \
    --region "$AWS_REGION" 2>/dev/null || \
aws cloudformation wait stack-update-complete \
    --stack-name "${STACK_PREFIX}-master" \
    --region "$AWS_REGION" 2>/dev/null || true

# Check if stack deployed successfully
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "FAILED")

if [[ "$STACK_STATUS" != *"COMPLETE"* ]]; then
    log_error "CloudFormation stack deployment failed with status: $STACK_STATUS"
    echo ""
    echo "Check the AWS CloudFormation console for detailed error messages:"
    echo "https://${AWS_REGION}.console.aws.amazon.com/cloudformation/home?region=${AWS_REGION}#/stacks"
    exit 1
fi

log_success "CloudFormation stack deployed successfully!"
echo ""

echo ""
log_info "=========================================="
log_info "Creating SSM Parameters"
log_info "=========================================="
log_info "Storing configuration in Systems Manager Parameter Store..."

# Create API Gateway URL parameter
API_GATEWAY_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiBaseUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null)

if [ -n "$API_GATEWAY_URL" ] && [ "$API_GATEWAY_URL" != "None" ]; then
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/api-base-url" \
        --value "$API_GATEWAY_URL" \
        --type String \
        --overwrite \
        --description "API Gateway base URL" \
        --region "$AWS_REGION" >/dev/null 2>&1 || true
    
    log_success "Created SSM parameter: /${STACK_PREFIX}/coveo/api-base-url"
fi

log_info "SSM parameters were already created before CloudFormation deployment"
log_success "All SSM secrets and parameters are ready!"
echo ""

# NOTE: AgentCore Runtime (MCP and Agent) deployment moved to separate steps
# MCP Server is deployed in Step 3 via scripts/deploy-mcp.sh
# Agent Runtime is deployed in Step 4 via scripts/deploy-agent.sh
# This ensures proper deployment order and uses the new CloudFormation + CodeBuild method

# Create placeholder SSM parameters for now (will be populated by MCP/Agent deployment)
log_info "Creating placeholder SSM parameters for AgentCore..."
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/coveo/runtime-id" \
    --value "PENDING_DEPLOYMENT" \
    --type String \
    --overwrite \
    --description "AgentCore Runtime - will be populated by MCP/Agent deployment" \
    --region "$AWS_REGION" >/dev/null 2>&1 || true

log_info "Placeholder parameters created. MCP and Agent will be deployed in separate steps."
echo ""



# Step 7: Build and push UI Docker image to ECR
# NOTE: UI deployment moved to Step 5 in deploy-complete-workshop.sh
# This ensures MCP and Agent are deployed before UI
log_info "Skipping UI deployment (will be done in Step 5 of complete deployment)..."

# Build UI Docker image
if false; then  # Disabled - UI deployed separately
if [ -f "frontend/Dockerfile" ]; then
    log_info "Checking for existing UI Docker image..."
    
    # Get ECR repository URI for UI
    UI_ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STACK_PREFIX}-ui"
    
    # Create ECR repository if it doesn't exist
    aws ecr describe-repositories --repository-names "${STACK_PREFIX}-ui" --region "$AWS_REGION" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${STACK_PREFIX}-ui" --region "$AWS_REGION" >/dev/null 2>&1
    
    # Check if UI rebuild is needed based on changes
    log_info "Checking if UI rebuild is needed..."
    
    EXISTING_UI_IMAGES=$(aws ecr list-images \
        --repository-name "${STACK_PREFIX}-ui" \
        --query 'imageIds[?imageTag==`latest`]' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_UI_IMAGES" ] && [ "$EXISTING_UI_IMAGES" != "None" ]; then
        log_info "Existing UI Docker image found, checking for changes..."
        
        UI_REBUILD_NEEDED=false
        UI_CHANGE_REASONS=()
        
        # Check 1: Frontend source code changes
        if [ -d "frontend" ]; then
            # Get image creation date
            UI_IMAGE_DATE=$(aws ecr describe-images \
                --repository-name "${STACK_PREFIX}-ui" \
                --image-ids imageTag=latest \
                --query 'imageDetails[0].imagePushedAt' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || echo "")
            
            if [ -n "$UI_IMAGE_DATE" ]; then
                # Check if any frontend files are newer than the image
                NEWER_FILES=$(find frontend -type f \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" -o -name "*.json" -o -name "Dockerfile" \) -newer <(date -d "$UI_IMAGE_DATE" +%Y%m%d%H%M%S) 2>/dev/null | head -5)
                
                if [ -n "$NEWER_FILES" ]; then
                    UI_CHANGE_REASONS+=("Frontend source files have been modified")
                    UI_REBUILD_NEEDED=true
                fi
            fi
        fi
        
        # Check 2: Environment configuration changes
        if [ -f ".env" ] && [ -n "$UI_IMAGE_DATE" ]; then
            ENV_MODIFIED=$(find .env -newer <(date -d "$UI_IMAGE_DATE" +%Y%m%d%H%M%S) 2>/dev/null || echo "")
            if [ -n "$ENV_MODIFIED" ]; then
                UI_CHANGE_REASONS+=("Environment configuration (.env) has been modified")
                UI_REBUILD_NEEDED=true
            fi
        fi
        
        # Check 3: Force rebuild (environment variable)
        if [ "$FORCE_UI_REBUILD" = "true" ]; then
            UI_CHANGE_REASONS+=("Forced UI rebuild requested via FORCE_UI_REBUILD=true")
            UI_REBUILD_NEEDED=true
        fi
        
        if [ "$UI_REBUILD_NEEDED" = "false" ]; then
            log_success "No UI changes detected"
            echo ""
            log_warning "Do you want to rebuild the UI Docker image anyway?"
            log_info "This will take 2-3 minutes but ensures you have the latest frontend code."
            echo ""
            read -p "Rebuild UI image? (y/N): " -n 1 -r
            echo ""
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "User requested UI rebuild"
                UI_REBUILD_NEEDED=true
            else
                log_success "Using existing UI Docker image"
            fi
        else
            log_warning "Changes detected that require UI rebuild:"
            for reason in "${UI_CHANGE_REASONS[@]}"; do
                echo "  - $reason"
            done
            log_info "Proceeding with automatic rebuild..."
        fi
        
        if [ "$UI_REBUILD_NEEDED" = "true" ]; then
            # Login to ECR
            aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            
            # Build and push Docker image
            cd frontend
            docker build --platform linux/amd64 -t "${STACK_PREFIX}-ui:latest" .
            docker tag "${STACK_PREFIX}-ui:latest" "$UI_ECR_REPO:latest"
            docker push "$UI_ECR_REPO:latest"
            cd ..
            
            log_success "UI Docker image rebuilt and pushed to ECR"
        fi
    else
        log_info "No existing UI image found, building new image..."
        
        # Login to ECR
        aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        
        # Build and push Docker image
        cd frontend
        docker build --platform linux/amd64 -t "${STACK_PREFIX}-ui:latest" .
        docker tag "${STACK_PREFIX}-ui:latest" "$UI_ECR_REPO:latest"
        docker push "$UI_ECR_REPO:latest"
        cd ..
        
        log_success "UI Docker image built and pushed to ECR"
    fi
else
    log_warning "Frontend Dockerfile not found, skipping UI Docker build"
fi
fi  # End of "if false" - UI build disabled

# Step 8: Deploy UI App Runner Stack
# NOTE: UI deployment moved to Step 5 in deploy-complete-workshop.sh
log_info "UI deployment will be done separately after MCP and Agent deployment"
# Disabled - UI deployed in Step 5 of complete deployment
if false; then
if [ -f "scripts/deploy-ui-stack.sh" ]; then
    chmod +x scripts/deploy-ui-stack.sh
    bash scripts/deploy-ui-stack.sh --stack-prefix "$STACK_PREFIX" --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        log_success "UI App Runner stack deployed successfully"
    else
        log_warning "UI App Runner stack deployment had issues, but continuing..."
    fi
else
    log_warning "UI deployment script not found"
fi
fi  # End of disabled UI deployment

# Deployment complete - outputs will be shown by orchestration script
log_success "Main infrastructure deployment complete"

exit 0
