#!/bin/bash

# =============================================================================
# Pre-deployment Validation Script
# =============================================================================
# Validates prerequisites before running the complete deployment:
# - AWS CLI and credentials
# - Docker installation and daemon
# - Required environment variables
# - Required files and permissions
# =============================================================================

set -e

# Configuration
STACK_PREFIX="workshop"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Pre-deployment Validation${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

VALIDATION_FAILED=false

# =============================================================================
# Check AWS CLI
# =============================================================================
print_status "Checking AWS CLI installation..." "INFO"
if command_exists aws; then
    AWS_CLI_VERSION=$(aws --version 2>&1 | head -n1)
    print_status "AWS CLI found: $AWS_CLI_VERSION" "SUCCESS"
else
    print_status "AWS CLI not found - Please install AWS CLI v2" "ERROR"
    VALIDATION_FAILED=true
fi

# =============================================================================
# Get AWS Account ID (without credential validation)
# =============================================================================
print_status "Getting AWS account information..." "INFO"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -n "$AWS_ACCOUNT_ID" ]; then
    AWS_USER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "")
    print_status "AWS account detected" "SUCCESS"
    echo -e "  ${BLUE}Account ID: $AWS_ACCOUNT_ID${NC}"
    echo -e "  ${BLUE}User/Role: $AWS_USER_ARN${NC}"
else
    print_status "Could not retrieve AWS account info (credentials may not be configured)" "WARNING"
fi

# =============================================================================
# Check Docker
# =============================================================================
print_status "Checking Docker installation..." "INFO"
if command_exists docker; then
    DOCKER_VERSION=$(docker --version 2>&1)
    print_status "Docker found: $DOCKER_VERSION" "SUCCESS"
    
    # Check if Docker daemon is running
    if docker info >/dev/null 2>&1; then
        print_status "Docker daemon is running" "SUCCESS"
    else
        print_status "Docker daemon is not running - Please start Docker" "ERROR"
        VALIDATION_FAILED=true
    fi
else
    print_status "Docker not found - Please install Docker Desktop" "ERROR"
    VALIDATION_FAILED=true
fi

# =============================================================================
# Check Environment Variables
# =============================================================================
print_status "Checking environment variables..." "INFO"

# Load from .env if exists
if [ -f ".env" ]; then
    print_status "Loading from .env file" "INFO"
    set -a
    source .env
    set +a
elif [ -f "config/.env" ]; then
    print_status "Loading from config/.env file" "INFO"
    set -a
    source config/.env
    set +a
else
    print_status "No .env file found" "WARNING"
fi

# Check required variables
REQUIRED_VARS=("COVEO_ORG_ID" "COVEO_SEARCH_API_KEY" "COVEO_ANSWER_CONFIG_ID")
MISSING_VARS=()

for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        MISSING_VARS+=("$VAR")
        print_status "$VAR is NOT set" "ERROR"
    else
        print_status "$VAR is set" "SUCCESS"
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    print_status "Missing required variables: ${MISSING_VARS[*]}" "ERROR"
    print_status "Please set these in your .env file" "INFO"
    VALIDATION_FAILED=true
fi

# =============================================================================
# Check Required Files
# =============================================================================
print_status "Checking required files..." "INFO"

REQUIRED_FILES=(
    "cfn/master.yml"
    "cfn/auth-cognito.yml"
    "cfn/shared-core.yml"
    "cfn/ui-apprunner.yml"
    "scripts/deploy-main-infra.sh"
    "scripts/deploy-mcp.sh"
    "scripts/deploy-agent.sh"
    "scripts/deploy-ui-apprunner.sh"
    "frontend/Dockerfile"
    "frontend/server.js"
)

for FILE in "${REQUIRED_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        print_status "$FILE exists" "SUCCESS"
    else
        print_status "$FILE missing" "ERROR"
        VALIDATION_FAILED=true
    fi
done

# =============================================================================
# Check AWS Permissions
# =============================================================================
print_status "Checking AWS permissions..." "INFO"

# Test CloudFormation permissions
if aws cloudformation list-stacks --region "$AWS_REGION" >/dev/null 2>&1; then
    print_status "CloudFormation permissions OK" "SUCCESS"
else
    print_status "CloudFormation permissions missing" "ERROR"
    VALIDATION_FAILED=true
fi

# Test S3 permissions
if aws s3 ls >/dev/null 2>&1; then
    print_status "S3 permissions OK" "SUCCESS"
else
    print_status "S3 permissions missing" "ERROR"
    VALIDATION_FAILED=true
fi

# Test ECR permissions
if aws ecr describe-repositories --region "$AWS_REGION" >/dev/null 2>&1; then
    print_status "ECR permissions OK" "SUCCESS"
else
    print_status "ECR permissions missing" "ERROR"
    VALIDATION_FAILED=true
fi

# =============================================================================
# Check Existing Resources
# =============================================================================
print_status "Checking for existing resources..." "INFO"

# Check for existing stacks
EXISTING_STACKS=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query "StackSummaries[?starts_with(StackName, '${STACK_PREFIX}')].StackName" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$EXISTING_STACKS" ]; then
    print_status "Existing stacks found (will be updated): $EXISTING_STACKS" "WARNING"
else
    print_status "No existing stacks found (fresh deployment)" "INFO"
fi

# Check for existing S3 buckets
CFN_BUCKET_NAME="workshop-${AWS_ACCOUNT_ID}-cfn-templates"
UI_BUCKET_NAME="workshop-${AWS_ACCOUNT_ID}-ui"

if aws s3 ls "s3://${CFN_BUCKET_NAME}" --region "$AWS_REGION" >/dev/null 2>&1; then
    print_status "CFN bucket exists: $CFN_BUCKET_NAME" "INFO"
else
    print_status "CFN bucket will be created: $CFN_BUCKET_NAME" "INFO"
fi

if aws s3 ls "s3://${UI_BUCKET_NAME}" --region "$AWS_REGION" >/dev/null 2>&1; then
    print_status "UI bucket exists: $UI_BUCKET_NAME" "INFO"
else
    print_status "UI bucket will be created: $UI_BUCKET_NAME" "INFO"
fi

# =============================================================================
# Validation Summary
# =============================================================================
echo ""
if [ "$VALIDATION_FAILED" = true ]; then
    echo -e "${RED}==============================================================================${NC}"
    echo -e "${RED}❌ Validation Failed${NC}"
    echo -e "${RED}==============================================================================${NC}"
    echo ""
    echo -e "${YELLOW}Please fix the errors above before deploying${NC}"
    echo ""
    exit 1
else
    echo -e "${GREEN}==============================================================================${NC}"
    echo -e "${GREEN}✅ Validation Successful${NC}"
    echo -e "${GREEN}==============================================================================${NC}"
    echo ""
    echo -e "${YELLOW}Ready to deploy:${NC}"
    echo -e "  Stack Prefix: $STACK_PREFIX"
    echo -e "  AWS Region: $AWS_REGION"
    echo -e "  AWS Account: $AWS_ACCOUNT_ID"
    echo -e "  Coveo Org ID: $COVEO_ORG_ID"
    echo ""
    exit 0
fi
