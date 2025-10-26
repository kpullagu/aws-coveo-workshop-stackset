#!/bin/bash
#
# Enable Bedrock Model Invocation Logging
# This configures Bedrock to log all model invocations to CloudWatch
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ASSUME_ROLE_NAME="${ASSUME_ROLE_NAME:-OrganizationAccountAccessRole}"

log_info "=========================================="
log_info "Enable Bedrock Model Invocation Logging"
log_info "=========================================="

# Get list of accounts
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

ACCOUNT_COUNT=$(echo $ACCOUNT_IDS | wc -w)
log_info "Found $ACCOUNT_COUNT accounts to configure"
echo ""

COUNTER=1
for ACCOUNT_ID in $ACCOUNT_IDS; do
    log_info "=========================================="
    log_info "[$COUNTER/$ACCOUNT_COUNT] Configuring Account: $ACCOUNT_ID"
    log_info "=========================================="
    
    # Clear credentials
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    
    # Assume role
    CREDS=$(aws sts assume-role \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}" \
        --role-session-name "bedrock-logs-${ACCOUNT_ID}" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "Cannot assume role"
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
    export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
    
    # Find the Layer 3 stack name
    STACK_NAME=$(aws cloudformation list-stacks \
        --region "$AWS_REGION" \
        --query "StackSummaries[?contains(StackName, 'StackSet-${STACK_PREFIX}-layer3-ai-services') && StackStatus!='DELETE_COMPLETE'].StackName | [0]" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$STACK_NAME" ] || [ "$STACK_NAME" == "None" ]; then
        log_warning "Layer 3 stack not found, skipping"
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    log_info "Stack: $STACK_NAME"
    
    # Determine log group name
    MODEL_LG_NAME="/aws/bedrock/modelinvocations/${STACK_NAME}"
    
    # Check if log group exists, if not use a generic name
    EXISTING_LG=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/bedrock/modelinvocations/" \
        --region "$AWS_REGION" \
        --query "logGroups[0].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_LG" ] && [ "$EXISTING_LG" != "None" ]; then
        MODEL_LG_NAME="$EXISTING_LG"
        log_info "Using existing log group: $MODEL_LG_NAME"
    else
        log_info "Will use log group: $MODEL_LG_NAME"
    fi
    
    # Construct logs role ARN
    LOGS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${STACK_PREFIX}-bedrock-modelinv-logs-role"
    
    log_info "Logs Role ARN: $LOGS_ROLE_ARN"
    
    # Check if role exists
    if ! aws iam get-role --role-name "${STACK_PREFIX}-bedrock-modelinv-logs-role" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_error "Bedrock model invocation logs role not found"
        log_info "Deploy Layer 3 first to create the role"
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    # Enable model invocation logging
    log_info "Enabling Bedrock model invocation logging..."
    
    aws bedrock put-model-invocation-logging-configuration \
        --region "$AWS_REGION" \
        --logging-config "{
            \"cloudWatchConfig\": {
                \"logGroupName\": \"$MODEL_LG_NAME\",
                \"roleArn\": \"$LOGS_ROLE_ARN\"
            },
            \"textDataDeliveryEnabled\": true,
            \"imageDataDeliveryEnabled\": true,
            \"embeddingDataDeliveryEnabled\": true
        }" 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "✓ Model invocation logging enabled"
    else
        log_error "Failed to enable model invocation logging"
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    # Verify configuration
    log_info "Verifying configuration..."
    VERIFY=$(aws bedrock get-model-invocation-logging-configuration \
        --region "$AWS_REGION" \
        --query 'loggingConfig.cloudWatchConfig' \
        --output json 2>/dev/null || echo "{}")
    
    if [ -n "$VERIFY" ] && [ "$VERIFY" != "{}" ]; then
        log_success "✓ Configuration verified:"
        echo "$VERIFY" | jq '.'
    else
        log_warning "Could not verify configuration"
    fi
    
    log_success "Account $ACCOUNT_ID configured successfully!"
    echo ""
    
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    COUNTER=$((COUNTER + 1))
done

log_success "=========================================="
log_success "Configuration Complete!"
log_success "=========================================="
log_info "Bedrock model invocation logging is now enabled in all accounts."
log_info ""
log_info "You can view logs in CloudWatch:"
log_info "  Log Group: /aws/bedrock/modelinvocations/*"
log_info ""
log_info "Logs will include:"
log_info "  - Model input/output"
log_info "  - Token usage"
log_info "  - Latency metrics"
log_info "  - Error details"
