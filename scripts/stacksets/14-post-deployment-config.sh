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
log_info "  3. Cognito callback URLs"
log_info "  4. App Runner environment variables"
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

# Get list of accounts
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

ACCOUNT_COUNT=$(echo $ACCOUNT_IDS | wc -w)
log_info "Found $ACCOUNT_COUNT accounts to configure"
echo ""

# Create CSV header
echo "Account ID,Account Name,Region,App Runner URL,User Pool ID,Client ID,Cognito Domain,Test User Email,Test User Name,Password,Login URL,Status" > "$OUTPUT_FILE"

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
    ACCOUNT_OWNER=$(echo "$ACCOUNT_INFO" | jq -r '.Account.Email // "Unknown"')
    
    # Extract owner name from email (part before @) or use account name
    if [ "$ACCOUNT_OWNER" != "Unknown" ]; then
        ASSIGNED_USER=$(echo "$ACCOUNT_OWNER" | cut -d'@' -f1)
    else
        ASSIGNED_USER="$ACCOUNT_NAME"
    fi
    
    # Assume role
    CREDS=$(assume_role "$ACCOUNT_ID" 2>&1)
    if [ $? -ne 0 ]; then
        log_error "Cannot assume role"
        echo "$ACCOUNT_ID,\"$ACCOUNT_NAME\",$AWS_REGION,ERROR: Cannot assume role,,,,,$ASSIGNED_USER,,,FAILED" >> "$OUTPUT_FILE"
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
        echo "$ACCOUNT_ID,\"$ACCOUNT_NAME\",$AWS_REGION,No stacks deployed,,,,,$ASSIGNED_USER,,,FAILED" >> "$OUTPUT_FILE"
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
    
    # Step 4: Get App Runner URL
    log_info "Step 4: Getting App Runner URL..."
    
    APP_RUNNER_URL=""
    if [ -n "$UI_STACK" ] && [ "$UI_STACK" != "null" ]; then
        APP_RUNNER_URL=$(aws cloudformation describe-stacks \
            --stack-name "$UI_STACK" \
            --region "$AWS_REGION" \
            --query "Stacks[0].Outputs[?OutputKey=='ServiceUrl'].OutputValue" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$APP_RUNNER_URL" ]; then
        APP_RUNNER_URL="Not deployed"
    fi
    
    log_success "App Runner URL: https://$APP_RUNNER_URL"
    
    # Step 5: Update Cognito callback URLs
    if [ "$APP_RUNNER_URL" != "Not deployed" ]; then
        log_info "Step 5: Updating Cognito callback URLs..."
        
        aws cognito-idp update-user-pool-client \
            --user-pool-id "$USER_POOL_ID" \
            --client-id "$CLIENT_ID" \
            --callback-urls "https://$APP_RUNNER_URL" "http://localhost:3000" \
            --logout-urls "https://$APP_RUNNER_URL" "http://localhost:3000" \
            --allowed-o-auth-flows "code" \
            --allowed-o-auth-scopes "email" "openid" "profile" \
            --allowed-o-auth-flows-user-pool-client \
            --supported-identity-providers "COGNITO" \
            --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" "ALLOW_USER_SRP_AUTH" \
            --region "$AWS_REGION" >/dev/null 2>&1
        
        log_success "Callback URLs updated"
    fi
    
    # Step 6: Update App Runner environment variables
    if [ "$APP_RUNNER_URL" != "Not deployed" ]; then
        log_info "Step 6: Updating App Runner environment variables..."
        
        SERVICE_ARN=$(aws apprunner list-services \
            --region "$AWS_REGION" \
            --query "ServiceSummaryList[?contains(ServiceName, '${STACK_PREFIX}')].ServiceArn | [0]" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SERVICE_ARN" ] && [ "$SERVICE_ARN" != "None" ]; then
            # Get current config
            CURRENT_CONFIG=$(aws apprunner describe-service \
                --service-arn "$SERVICE_ARN" \
                --region "$AWS_REGION" \
                --output json)
            
            IMAGE_ID=$(echo "$CURRENT_CONFIG" | jq -r '.Service.SourceConfiguration.ImageRepository.ImageIdentifier')
            IMAGE_TYPE=$(echo "$CURRENT_CONFIG" | jq -r '.Service.SourceConfiguration.ImageRepository.ImageRepositoryType')
            PORT=$(echo "$CURRENT_CONFIG" | jq -r '.Service.SourceConfiguration.ImageRepository.ImageConfiguration.Port // "3003"')
            CURRENT_ENV_DICT=$(echo "$CURRENT_CONFIG" | jq -r '.Service.SourceConfiguration.ImageRepository.ImageConfiguration.RuntimeEnvironmentVariables // {}')
            
            # Add all required environment variables
            NEW_ENV_DICT=$(echo "$CURRENT_ENV_DICT" | jq \
                --arg pool "$USER_POOL_ID" \
                --arg client "$CLIENT_ID" \
                --arg domain "$COGNITO_DOMAIN" \
                --arg region "$AWS_REGION" \
                '. + {
                    COGNITO_USER_POOL_ID: $pool,
                    COGNITO_CLIENT_ID: $client,
                    COGNITO_DOMAIN: $domain,
                    COGNITO_REGION: $region
                }')
            
            # Create temp JSON
            TEMP_JSON=$(mktemp)
            cat > "$TEMP_JSON" <<EOF
{
  "ImageRepository": {
    "ImageIdentifier": "$IMAGE_ID",
    "ImageRepositoryType": "$IMAGE_TYPE",
    "ImageConfiguration": {
      "Port": "$PORT",
      "RuntimeEnvironmentVariables": $NEW_ENV_DICT
    }
  }
}
EOF
            
            # Update service
            aws apprunner update-service \
                --service-arn "$SERVICE_ARN" \
                --source-configuration file://"$TEMP_JSON" \
                --region "$AWS_REGION" >/dev/null 2>&1
            
            rm -f "$TEMP_JSON"
            
            log_success "App Runner environment variables updated"
            log_info "Waiting for service to restart..."
            sleep 30
        fi
    fi
    
    # Build login URL
    LOGIN_URL="N/A"
    if [ "$APP_RUNNER_URL" != "Not deployed" ] && [ -n "$COGNITO_DOMAIN" ]; then
        LOGIN_URL="https://${COGNITO_DOMAIN}.auth.${AWS_REGION}.amazoncognito.com/login?client_id=${CLIENT_ID}&response_type=code&redirect_uri=https://${APP_RUNNER_URL}"
    fi
    
    # Add to CSV (using assigned user from account owner)
    echo "$ACCOUNT_ID,\"$ACCOUNT_NAME\",$AWS_REGION,https://$APP_RUNNER_URL,$USER_POOL_ID,$CLIENT_ID,$COGNITO_DOMAIN,$TEST_USER_EMAIL,$ASSIGNED_USER,$TEST_USER_PASSWORD,$LOGIN_URL,SUCCESS" >> "$OUTPUT_FILE"
    
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
log_info "You can open this file in Excel"
log_info ""
log_info "Test credentials for all accounts:"
log_info "  Email: $TEST_USER_EMAIL"
log_info "  Password: $TEST_USER_PASSWORD"
