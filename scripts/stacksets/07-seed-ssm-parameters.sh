#!/bin/bash
#
# Seed SSM Parameters in all child accounts
# This MUST run BEFORE deploying Layer 2 (which creates Lambdas that need these parameters)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ASSUME_ROLE_NAME="${ASSUME_ROLE_NAME:-OrganizationAccountAccessRole}"

log_info "=========================================="
log_info "Seeding SSM Parameters"
log_info "=========================================="
log_info "This will seed Coveo credentials to all accounts"
log_info "MUST run BEFORE Layer 2 deployment!"
log_info "=========================================="

# Validate Coveo credentials
if [ -z "$COVEO_ORG_ID" ] || [ -z "$COVEO_SEARCH_API_KEY" ]; then
    log_error "Missing Coveo credentials!"
    log_info "Please set in .env.stacksets:"
    log_info "  COVEO_ORG_ID"
    log_info "  COVEO_SEARCH_API_KEY"
    log_info "  COVEO_PLATFORM_URL"
    log_info "  COVEO_SEARCH_PIPELINE"
    log_info "  COVEO_SEARCH_HUB"
    log_info "  COVEO_ANSWER_CONFIG_ID"
    exit 1
fi

# Set defaults for optional parameters (matching original deployment)
COVEO_PLATFORM_URL="${COVEO_PLATFORM_URL:-https://platform.cloud.coveo.com}"
COVEO_SEARCH_PIPELINE="${COVEO_SEARCH_PIPELINE:-aws-workshop-pipeline}"
COVEO_SEARCH_HUB="${COVEO_SEARCH_HUB:-aws-workshop}"
COVEO_ANSWER_CONFIG_ID="${COVEO_ANSWER_CONFIG_ID:-NOT_CONFIGURED}"

log_info "Coveo Org ID: $COVEO_ORG_ID"
log_info "API Key: ${COVEO_SEARCH_API_KEY:0:10}..."
log_info "Platform URL: $COVEO_PLATFORM_URL"
log_info "Search Pipeline: $COVEO_SEARCH_PIPELINE"
log_info "Search Hub: $COVEO_SEARCH_HUB"
log_info "Answer Config ID: $COVEO_ANSWER_CONFIG_ID"
echo ""

# Function to assume role
assume_role() {
    local account_id=$1
    aws sts assume-role \
        --role-arn "arn:aws:iam::${account_id}:role/${ASSUME_ROLE_NAME}" \
        --role-session-name "seed-ssm-${account_id}" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text
}

# Get list of accounts
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

ACCOUNT_COUNT=$(echo $ACCOUNT_IDS | wc -w)
log_info "Found $ACCOUNT_COUNT accounts to configure"
echo ""

COUNTER=1
SUCCESS_COUNT=0

for ACCOUNT_ID in $ACCOUNT_IDS; do
    log_info "[$COUNTER/$ACCOUNT_COUNT] Seeding SSM parameters in account: $ACCOUNT_ID"
    
    # Clear credentials
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    
    # Assume role
    CREDS=$(assume_role "$ACCOUNT_ID" 2>&1)
    if [ $? -ne 0 ]; then
        log_error "Cannot assume role"
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
    export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
    
    # Seed SSM Parameters (same as original seed-ssm-secrets.sh)
    log_info "  Creating /${STACK_PREFIX}/coveo/org-id"
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/org-id" \
        --value "$COVEO_ORG_ID" \
        --type "String" \
        --overwrite \
        --description "Coveo organization ID" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    log_info "  Creating /${STACK_PREFIX}/coveo/search-api-key"
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/search-api-key" \
        --value "$COVEO_SEARCH_API_KEY" \
        --type "String" \
        --overwrite \
        --description "Coveo Search API Key" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    log_info "  Creating /${STACK_PREFIX}/coveo/platform-url"
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/platform-url" \
        --value "$COVEO_PLATFORM_URL" \
        --type "String" \
        --overwrite \
        --description "Coveo Platform URL" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    log_info "  Creating /${STACK_PREFIX}/coveo/search-pipeline"
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/search-pipeline" \
        --value "$COVEO_SEARCH_PIPELINE" \
        --type "String" \
        --overwrite \
        --description "Coveo Search Pipeline" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    log_info "  Creating /${STACK_PREFIX}/coveo/search-hub"
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/search-hub" \
        --value "$COVEO_SEARCH_HUB" \
        --type "String" \
        --overwrite \
        --description "Coveo Search Hub" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    if [ -n "$COVEO_ANSWER_CONFIG_ID" ] && [ "$COVEO_ANSWER_CONFIG_ID" != "NOT_CONFIGURED" ]; then
        log_info "  Creating /${STACK_PREFIX}/coveo/answer-config-id"
        aws ssm put-parameter \
            --name "/${STACK_PREFIX}/coveo/answer-config-id" \
            --value "$COVEO_ANSWER_CONFIG_ID" \
            --type "String" \
            --overwrite \
            --description "Coveo Answer API configuration ID" \
            --region "$AWS_REGION" >/dev/null 2>&1
    fi
    
    log_success "Account $ACCOUNT_ID: SSM parameters seeded"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    COUNTER=$((COUNTER + 1))
done

echo ""
log_success "=========================================="
log_success "SSM Parameters Seeded!"
log_success "=========================================="
log_success "Successfully configured: $SUCCESS_COUNT/$ACCOUNT_COUNT accounts"
log_info ""
log_info "Seeded parameters:"
log_info "  - /${STACK_PREFIX}/coveo/org-id"
log_info "  - /${STACK_PREFIX}/coveo/search-api-key"
log_info "  - /${STACK_PREFIX}/coveo/platform-url"
log_info "  - /${STACK_PREFIX}/coveo/search-pipeline"
log_info "  - /${STACK_PREFIX}/coveo/search-hub"
log_info "  - /${STACK_PREFIX}/coveo/answer-config-id"
log_info ""
log_info "Note: Layer 2 will create additional parameters:"
log_info "  - /${STACK_PREFIX}/coveo/user-pool-id"
log_info "  - /${STACK_PREFIX}/coveo/client-id"
log_info "  - /${STACK_PREFIX}/coveo/cognito-domain"
log_info "  - /${STACK_PREFIX}/coveo/api-base-url"
log_info ""
log_info "Ready to deploy Layer 2!"
