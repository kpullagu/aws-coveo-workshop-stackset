#!/bin/bash
#
# Seed SSM Parameter Store and Secrets Manager with Coveo credentials
#
# Usage:
#   ./scripts/seed-ssm-secrets.sh [--stack-prefix NAME] [--region REGION]
#

set -e

# Fixed values for consistency
STACK_PREFIX="workshop"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stack-prefix)
            STACK_PREFIX="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--stack-prefix NAME] [--region REGION]"
            exit 1
            ;;
    esac
done

# Load from .env if exists (try multiple locations)
if [ -f ".env" ]; then
    log_info "Loading credentials from .env"
    set -a
    source .env
    set +a
elif [ -f "config/.env" ]; then
    log_info "Loading credentials from config/.env"
    set -a
    source config/.env
    set +a
fi

echo "========================================"
echo " Seeding Secrets to AWS"
echo "========================================"
echo "  Stack Prefix: $STACK_PREFIX (fixed)"
echo "  Region:       $AWS_REGION"
echo "========================================"
echo ""

# Validate required variables
REQUIRED_VARS=("COVEO_ORG_ID" "COVEO_SEARCH_API_KEY" "COVEO_ANSWER_CONFIG_ID")
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        log_warning "$VAR not set, please enter it:"
        read -p "$VAR: " VALUE
        export "$VAR=$VALUE"
    fi
done

# 1. Put Coveo Org ID in SSM Parameter Store
log_info "Storing Coveo Org ID in SSM Parameter Store..."
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/coveo/org-id" \
    --value "$COVEO_ORG_ID" \
    --type "String" \
    --overwrite \
    --description "Coveo organization ID" \
    --region "$AWS_REGION" > /dev/null

log_success "Stored: /${STACK_PREFIX}/coveo/org-id"

# 2. Put Coveo Answer Config ID in SSM
log_info "Storing Coveo Answer Config ID in SSM..."
if [ -n "$COVEO_ANSWER_CONFIG_ID" ] && [ "$COVEO_ANSWER_CONFIG_ID" != "NOT_CONFIGURED" ]; then
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/answer-config-id" \
        --value "$COVEO_ANSWER_CONFIG_ID" \
        --type "String" \
        --overwrite \
        --description "Coveo Answer API configuration ID" \
        --region "$AWS_REGION" > /dev/null
    
    log_success "Stored: /${STACK_PREFIX}/coveo/answer-config-id"
else
    log_warning "COVEO_ANSWER_CONFIG_ID is empty or not configured, skipping SSM parameter creation"
fi

# 3. Put Coveo Search API Key in Secrets Manager
log_info "Storing Coveo Search API Key in Secrets Manager..."
aws secretsmanager create-secret \
    --name "${STACK_PREFIX}/coveo/search-api-key" \
    --secret-string "$COVEO_SEARCH_API_KEY" \
    --region "$AWS_REGION" 2>/dev/null || \
aws secretsmanager update-secret \
    --secret-id "${STACK_PREFIX}/coveo/search-api-key" \
    --secret-string "$COVEO_SEARCH_API_KEY" \
    --region "$AWS_REGION" > /dev/null

log_success "Stored: ${STACK_PREFIX}/coveo/search-api-key (Secrets Manager)"

# 4. Also store API Key in SSM Parameter Store as SecureString
log_info "Storing Coveo Search API Key in SSM Parameter Store (SecureString)..."
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/coveo/search-api-key" \
    --value "$COVEO_SEARCH_API_KEY" \
    --type "SecureString" \
    --overwrite \
    --region "$AWS_REGION" > /dev/null

log_success "Stored: /${STACK_PREFIX}/coveo/search-api-key (SSM SecureString)"

echo ""
log_success "All secrets seeded successfully! 🎉"
echo ""
echo "Lambdas will now be able to access Coveo APIs using these credentials."
echo ""

exit 0
