#!/bin/bash
#
# Configuration file for StackSets deployment
# Loads all settings from .env.stacksets
#

# Color codes for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Find and load .env.stacksets
ENV_FILE=""
if [ -f ".env.stacksets" ]; then
    ENV_FILE=".env.stacksets"
elif [ -f "../../.env.stacksets" ]; then
    ENV_FILE="../../.env.stacksets"
elif [ -f "../.env.stacksets" ]; then
    ENV_FILE="../.env.stacksets"
fi

if [ -n "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo -e "${RED}ERROR: .env.stacksets file not found!${NC}"
    echo -e "${YELLOW}Please create .env.stacksets from .env.stacksets.example${NC}"
    echo ""
    echo "Steps:"
    echo "  1. cp .env.stacksets.example .env.stacksets"
    echo "  2. Edit .env.stacksets with your values"
    echo "  3. Run this script again"
    exit 1
fi

# Validate required variables
REQUIRED_VARS=(
    "MASTER_ACCOUNT_ID"
    "OU_ID"
    "AWS_REGION"
    "STACK_PREFIX"
)

MISSING_VARS=()
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        MISSING_VARS+=("$VAR")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}ERROR: Missing required configuration in .env.stacksets:${NC}"
    for VAR in "${MISSING_VARS[@]}"; do
        echo -e "  ${YELLOW}- $VAR${NC}"
    done
    echo ""
    echo "Please update your .env.stacksets file"
    exit 1
fi

# Set defaults for optional variables
export TEST_USER_EMAIL="${TEST_USER_EMAIL:-workshop-user@example.com}"
export TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-ChangeMe123!}"
export BEDROCK_MODEL="${BEDROCK_MODEL:-us.amazon.nova-lite-v1:0}"
export MAX_CONCURRENT_ACCOUNTS="${MAX_CONCURRENT_ACCOUNTS:-10}"
export FAILURE_TOLERANCE_COUNT="${FAILURE_TOLERANCE_COUNT:-5}"
export ASSUME_ROLE_NAME="${ASSUME_ROLE_NAME:-OrganizationAccountAccessRole}"

# Cognito Configuration
export COGNITO_DOMAIN_PREFIX_FORMAT="workshop"  # Will be: workshop-{AccountId}

# Bedrock Configuration (loaded from .env.stacksets, default set above)

# App Runner Configuration
export APPRUNNER_CPU="1024"      # 1 vCPU
export APPRUNNER_MEMORY="2048"   # 2 GB

# Lambda Layer Configuration
export USE_SHARED_LAMBDA_LAYER="true"  # Shared from master account

# Deployment Configuration
export MAX_CONCURRENT_ACCOUNTS="10"     # Deploy to 10 accounts at a time
export FAILURE_TOLERANCE_COUNT="5"      # Allow 5 failures before stopping

# ECR Configuration
export MCP_SERVER_REPO_NAME="${STACK_PREFIX}-coveo-mcp-server-master"
export UI_REPO_NAME="${STACK_PREFIX}-ui-master"

# S3 Configuration
export CFN_BUCKET_PREFIX="${STACK_PREFIX}"  # Will be: workshop-{AccountId}-cfn-templates

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Helper functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Validate required environment variables
validate_env() {
    local missing=()
    
    if [ -z "$COVEO_ORG_ID" ]; then missing+=("COVEO_ORG_ID"); fi
    if [ -z "$COVEO_SEARCH_API_KEY" ]; then missing+=("COVEO_SEARCH_API_KEY"); fi
    if [ -z "$COVEO_ANSWER_CONFIG_ID" ]; then missing+=("COVEO_ANSWER_CONFIG_ID"); fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required environment variables: ${missing[*]}"
        echo "Please set these variables before running deployment:"
        for var in "${missing[@]}"; do
            echo "  export $var=\"your-value\""
        done
        return 1
    fi
    
    return 0
}

# Display configuration
show_config() {
    echo ""
    log_info "=========================================="
    log_info "Deployment Configuration"
    log_info "=========================================="
    echo "Master Account ID: $MASTER_ACCOUNT_ID"
    echo "OU ID: $OU_ID"
    echo "AWS Region: $AWS_REGION"
    echo "Stack Prefix: $STACK_PREFIX"
    echo "Test User: $TEST_USER_EMAIL"
    echo "Bedrock Model: $BEDROCK_MODEL"
    echo "Shared Lambda Layer: $USE_SHARED_LAMBDA_LAYER"
    echo "Max Concurrent: $MAX_CONCURRENT_ACCOUNTS accounts"
    echo "Failure Tolerance: $FAILURE_TOLERANCE_COUNT accounts"
    echo ""
}
