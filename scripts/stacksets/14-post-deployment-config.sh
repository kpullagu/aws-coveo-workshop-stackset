#!/bin/bash
#
# Post-Deployment Configuration
# Consolidates: Cognito setup, test users, callback URLs, SSM secrets, and deployment info collection
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ASSUME_ROLE_NAME="${ASSUME_ROLE_NAME:-OrganizationAccountAccessRole}"
OUTPUT_FILE="workshop-deployment-info.csv"

log_info "=========================================="
log_info "Post-Deployment Configuration"
log_info "=========================================="
log_info "This will configure all accounts with:"
log_info "  1. SSM Parameters (Coveo credentials)"
log_info "  2. Cognito test users"
log_info "  3. Hosted MCP parameter validation"
log_info "  4. Cognito callback URLs"
log_info "  5. Collect deployment information"
log_info "=========================================="

# Validate Coveo credentials
if [ -z "$COVEO_ORG_ID" ] || [ -z "$COVEO_SEARCH_API_KEY" ]; then
    log_error "Missing Coveo credentials!"
    log_info "Please set in .env.stacksets:"
    log_info "  COVEO_ORG_ID"
    log_info "  COVEO_SEARCH_API_KEY"
    log_info "  COVEO_ANSWER_CONFIG_ID"
    exit 1
fi

# Function to assume role
assume_role() {
    local account_id=$1
    aws sts assume-role \
        --role-arn "arn:aws:iam::${account_id}:role/${ASSUME_ROLE_NAME}" \
        --role-session-name "post-config-${account_id}" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text
}

normalize_service_url() {
    local raw_url="$1"
    if [ -z "$raw_url" ] || [ "$raw_url" = "None" ] || [ "$raw_url" = "Not deployed" ]; then
        echo "Not deployed"
    elif [[ "$raw_url" == http://* || "$raw_url" == https://* ]]; then
        echo "$raw_url"
    else
        echo "https://$raw_url"
    fi
}

# Get list of accounts
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

ACCOUNT_COUNT=$(echo $ACCOUNT_IDS | wc -w)
log_info "Found $ACCOUNT_COUNT accounts to configure"
echo ""

# AWS Access Portal URL (fixed)
AWS_ACCESS_PORTAL="https://d-90662c5a64.awsapps.com/start"

# UI Login credentials (from .env.stacksets)
UI_LOGIN_USERNAME="${TEST_USER_EMAIL}"
UI_LOGIN_PASSWORD="${TEST_USER_PASSWORD}"

# Create CSV header (tab-separated)
echo -e "AWS Access Portal\tAWS Account ID\tAWS Account Name\tAWS User Name\tAWS Password\tUI URL\tUI User Login User Name\tUI Login Password" > "$OUTPUT_FILE"

COUNTER=1
for ACCOUNT_ID in $ACCOUNT_IDS; do
    log_info "=========================================="
    log_info "[$COUNTER/$ACCOUNT_COUNT] Configuring Account: $ACCOUNT_ID"
    log_info "=========================================="
    
    # Clear credentials
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    
    # Get account name and owner
    ACCOUNT_INFO=$(aws organizations describe-account \
        --account-id "$ACCOUNT_ID" \
        --output json 2>/dev/null || echo "{}")
    
    ACCOUNT_NAME=$(echo "$ACCOUNT_INFO" | jq -r '.Account.Name // "Unknown"')
    
    # Extract last digits after the last hyphen in account name for AWS username
    # Example: "workshop-account-1" -> "workshop-user1"
    LAST_DIGITS=$(echo "$ACCOUNT_NAME" | grep -oE '[0-9]+$' || echo "")
    if [ -n "$LAST_DIGITS" ]; then
        AWS_USERNAME="workshop-user${LAST_DIGITS}"
    else
        # Fallback: use counter if no digits found
        AWS_USERNAME="workshop-user${COUNTER}"
    fi
    
    # Assume role
    CREDS=$(assume_role "$ACCOUNT_ID" 2>&1)
    if [ $? -ne 0 ]; then
        log_error "Cannot assume role"
        echo -e "${AWS_ACCESS_PORTAL}\t${ACCOUNT_ID}\t${ACCOUNT_NAME}\t${AWS_USERNAME}\t\tERROR: Cannot assume role\t${UI_LOGIN_USERNAME}\t${UI_LOGIN_PASSWORD}" >> "$OUTPUT_FILE"
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
    export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
    
    # Step 1: Seed SSM Parameters (Coveo credentials only)
    log_info "Step 1: Seeding Coveo SSM Parameters..."
    log_info "Note: Agent parameters already seeded in Step 8.5"
    
    # Coveo credentials
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/org-id" \
        --value "$COVEO_ORG_ID" \
        --type "String" \
        --overwrite \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/search-api-key" \
        --value "$COVEO_SEARCH_API_KEY" \
        --type "String" \
        --overwrite \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    if [ -n "$COVEO_ANSWER_CONFIG_ID" ]; then
        aws ssm put-parameter \
            --name "/${STACK_PREFIX}/coveo/answer-config-id" \
            --value "$COVEO_ANSWER_CONFIG_ID" \
            --type "String" \
            --overwrite \
            --region "$AWS_REGION" >/dev/null 2>&1
    fi
    
    log_success "Coveo SSM parameters seeded"
    
    # Find stacks
    CORE_STACK=$(aws cloudformation list-stacks \
        --region "$AWS_REGION" \
        --query "StackSummaries[?contains(StackName, 'StackSet-${STACK_PREFIX}-layer2-core') && StackStatus!='DELETE_COMPLETE'].StackName | [0]" \
        --output json 2>/dev/null | jq -r '.' || echo "")
    
    UI_STACK=$(aws cloudformation list-stacks \
        --region "$AWS_REGION" \
        --query "StackSummaries[?contains(StackName, 'StackSet-${STACK_PREFIX}-layer4-ui') && StackStatus!='DELETE_COMPLETE'].StackName | [0]" \
        --output json 2>/dev/null | jq -r '.' || echo "")
    
    if [ -z "$CORE_STACK" ] || [ "$CORE_STACK" == "null" ]; then
        log_error "No Layer 2 stack found"
        echo -e "${AWS_ACCESS_PORTAL}\t${ACCOUNT_ID}\t${ACCOUNT_NAME}\t${AWS_USERNAME}\t\tNo stacks deployed\t${UI_LOGIN_USERNAME}\t${UI_LOGIN_PASSWORD}" >> "$OUTPUT_FILE"
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    # Step 2: Get Cognito details
    log_info "Step 2: Getting Cognito configuration..."
    
    USER_POOL_ID=$(aws cloudformation describe-stacks \
        --stack-name "$CORE_STACK" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    CLIENT_ID=$(aws cloudformation describe-stacks \
        --stack-name "$CORE_STACK" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    COGNITO_DOMAIN=$(aws cognito-idp describe-user-pool \
        --user-pool-id "$USER_POOL_ID" \
        --region "$AWS_REGION" \
        --query 'UserPool.Domain' \
        --output text 2>/dev/null || echo "")
    
    log_success "Cognito details retrieved"
    
    # Step 3: Create test user
    log_info "Step 3: Creating test user..."
    
    set +e
    aws cognito-idp admin-create-user \
        --user-pool-id "$USER_POOL_ID" \
        --username "$TEST_USER_EMAIL" \
        --user-attributes \
            Name=email,Value="$TEST_USER_EMAIL" \
            Name=email_verified,Value=true \
        --message-action SUPPRESS \
        --region "$AWS_REGION" 2>/dev/null
    set -e
    
    aws cognito-idp admin-set-user-password \
        --user-pool-id "$USER_POOL_ID" \
        --username "$TEST_USER_EMAIL" \
        --password "$TEST_USER_PASSWORD" \
        --permanent \
        --region "$AWS_REGION" 2>/dev/null
    
    log_success "Test user configured"
    
    # Step 4: Validate Hosted MCP parameters and get UI service URL
    log_info "Step 4: Validating Hosted MCP parameters and getting UI service URL..."

    for PARAM_NAME in \
        "/${STACK_PREFIX}/coveo/hosted-mcp-config-name" \
        "/${STACK_PREFIX}/coveo/hosted-mcp-endpoint" \
        "/${STACK_PREFIX}/coveo/hosted-mcp-auth-mode" \
        "/${STACK_PREFIX}/coveo/hosted-mcp-api-key" \
        "/${STACK_PREFIX}/coveo/hosted-mcp-search-hub"; do
        if ! aws ssm get-parameter \
            --name "$PARAM_NAME" \
            --with-decryption \
            --region "$AWS_REGION" >/dev/null 2>&1; then
            log_error "Missing required Hosted MCP parameter: $PARAM_NAME"
            echo -e "${AWS_ACCESS_PORTAL}\t${ACCOUNT_ID}\t${ACCOUNT_NAME}\t${AWS_USERNAME}\t\tERROR: Missing Hosted MCP SSM parameters\t${UI_LOGIN_USERNAME}\t${UI_LOGIN_PASSWORD}" >> "$OUTPUT_FILE"
            unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
            COUNTER=$((COUNTER + 1))
            continue
        fi
    done

    UI_SERVICE_URL=""
    if [ -n "$UI_STACK" ] && [ "$UI_STACK" != "null" ]; then
        UI_SERVICE_URL=$(aws cloudformation describe-stacks \
            --stack-name "$UI_STACK" \
            --region "$AWS_REGION" \
            --query "Stacks[0].Outputs[?OutputKey=='ServiceUrl'].OutputValue" \
            --output text 2>/dev/null || echo "")
    fi

    FORMATTED_UI_URL=$(normalize_service_url "$UI_SERVICE_URL")
    log_success "UI URL: $FORMATTED_UI_URL"

    # Step 5: Update Cognito callback URLs
    if [ "$FORMATTED_UI_URL" != "Not deployed" ]; then
        log_info "Step 5: Updating Cognito callback URLs..."
        
        aws cognito-idp update-user-pool-client \
            --user-pool-id "$USER_POOL_ID" \
            --client-id "$CLIENT_ID" \
            --callback-urls "$FORMATTED_UI_URL" "http://localhost:3000" \
            --logout-urls "$FORMATTED_UI_URL" "http://localhost:3000" \
            --allowed-o-auth-flows "code" \
            --allowed-o-auth-scopes "email" "openid" "profile" \
            --allowed-o-auth-flows-user-pool-client \
            --supported-identity-providers "COGNITO" \
            --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" "ALLOW_USER_SRP_AUTH" \
            --region "$AWS_REGION" >/dev/null 2>&1
        
        log_success "Callback URLs updated"
    fi

    # Add to CSV (tab-separated)
    # Format: AWS Access Portal, AWS Account ID, AWS Account Name, AWS User Name, AWS Password (empty), UI URL, UI User Login User Name, UI Login Password
    echo -e "${AWS_ACCESS_PORTAL}\t${ACCOUNT_ID}\t${ACCOUNT_NAME}\t${AWS_USERNAME}\t\t${FORMATTED_UI_URL}\t${UI_LOGIN_USERNAME}\t${UI_LOGIN_PASSWORD}" >> "$OUTPUT_FILE"
    
    log_success "Account $ACCOUNT_ID configured successfully!"
    echo ""
    
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    COUNTER=$((COUNTER + 1))
done

log_success "=========================================="
log_success "Configuration Complete!"
log_success "=========================================="
log_info "Deployment information saved to: $OUTPUT_FILE"
log_info ""
log_info "CSV Format (tab-separated):"
log_info "  - AWS Access Portal: $AWS_ACCESS_PORTAL"
log_info "  - AWS User Names: workshop-user1, workshop-user2, etc."
log_info "  - UI Login: $UI_LOGIN_USERNAME / $UI_LOGIN_PASSWORD"
log_info ""
log_info "You can open this file in Excel or any spreadsheet application"
log_info ""
log_info "Cognito test credentials (for backend testing):"
log_info "  Email: $TEST_USER_EMAIL"
log_info "  Password: $TEST_USER_PASSWORD"
