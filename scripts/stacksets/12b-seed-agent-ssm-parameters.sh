#!/bin/bash
#
# Seed Agent SSM Parameters (Run immediately after Layer 3 deployment)
# Creates SSM parameters needed by the Agent Runtime
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ASSUME_ROLE_NAME="${ASSUME_ROLE_NAME:-OrganizationAccountAccessRole}"

log_info "=========================================="
log_info "Seeding Agent SSM Parameters"
log_info "=========================================="
log_info "Layer 3 CloudFormation already created:"
log_info "  - /${STACK_PREFIX}/coveo/runtime-arn (Agent Runtime ARN)"
log_info "  - /${STACK_PREFIX}/coveo/mcp-runtime-arn (MCP Runtime ARN)"
log_info ""
log_info "This script creates additional parameters needed by Agent:"
log_info "  - /${STACK_PREFIX}/aws-region"
log_info "  - /${STACK_PREFIX}/coveo/bedrock-model-id"
log_info "  - /${STACK_PREFIX}/coveo/mcp-url (constructed from mcp-runtime-arn)"
log_info "=========================================="

# Function to assume role
assume_role() {
    local account_id=$1
    aws sts assume-role \
        --role-arn "arn:aws:iam::${account_id}:role/${ASSUME_ROLE_NAME}" \
        --role-session-name "seed-agent-ssm-${account_id}" \
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
    log_info "[$COUNTER/$ACCOUNT_COUNT] Seeding Agent SSM parameters in account: $ACCOUNT_ID"
    
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
    
    # Find Layer 3 AI services stack
    AI_STACK=$(aws cloudformation list-stacks \
        --region "$AWS_REGION" \
        --query "StackSummaries[?contains(StackName, 'StackSet-${STACK_PREFIX}-layer3-ai-services') && StackStatus!='DELETE_COMPLETE'].StackName | [0]" \
        --output json 2>/dev/null | jq -r '.' || echo "")
    
    if [ -z "$AI_STACK" ] || [ "$AI_STACK" == "null" ]; then
        log_warning "No Layer 3 stack found, skipping"
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    log_info "  Found AI stack: $AI_STACK"
    
    # Get MCP Runtime ARN from SSM (created by Layer 3 CloudFormation)
    MCP_RUNTIME_ARN=$(aws ssm get-parameter \
        --name "/${STACK_PREFIX}/coveo/mcp-runtime-arn" \
        --region "$AWS_REGION" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$MCP_RUNTIME_ARN" ] || [ "$MCP_RUNTIME_ARN" == "None" ]; then
        log_error "  Could not find MCP Runtime ARN in SSM (should be created by Layer 3 CFN)"
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    log_info "  MCP Runtime ARN: $MCP_RUNTIME_ARN"
    
    # Construct MCP URL from runtime ARN
    # Format: https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{encoded-arn}/invocations?qualifier=DEFAULT
    # URL encode the ARN
    ENCODED_ARN=$(echo -n "$MCP_RUNTIME_ARN" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=''))")
    MCP_URL="https://bedrock-agentcore.${AWS_REGION}.amazonaws.com/runtimes/${ENCODED_ARN}/invocations?qualifier=DEFAULT"
    
    log_info "  MCP URL: $MCP_URL"
    
    # Create additional Agent SSM parameters (runtime-arn and mcp-runtime-arn already created by CFN)
    log_info "  Creating /${STACK_PREFIX}/aws-region"
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/aws-region" \
        --value "$AWS_REGION" \
        --type "String" \
        --overwrite \
        --description "AWS Region for the deployment" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    log_info "  Creating /${STACK_PREFIX}/coveo/bedrock-model-id"
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/bedrock-model-id" \
        --value "$BEDROCK_MODEL" \
        --type "String" \
        --overwrite \
        --description "Bedrock model ID for the Agent" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    log_info "  Creating /${STACK_PREFIX}/coveo/mcp-url"
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/mcp-url" \
        --value "$MCP_URL" \
        --type "String" \
        --overwrite \
        --description "MCP Runtime invocation URL (constructed from mcp-runtime-arn)" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    # Grant SSM permissions to agent execution role
    AGENT_ROLE_NAME="${STACK_PREFIX}-agent-execution-role"
    
    # Check if role exists
    ROLE_EXISTS=$(aws iam get-role \
        --role-name "$AGENT_ROLE_NAME" \
        2>/dev/null || echo "")
    
    if [ -n "$ROLE_EXISTS" ]; then
        log_info "  Adding SSM permissions to $AGENT_ROLE_NAME"
        
        # Create inline policy for SSM access
        cat > /tmp/ssm-policy-$ACCOUNT_ID.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": [
        "arn:aws:ssm:${AWS_REGION}:${ACCOUNT_ID}:parameter/${STACK_PREFIX}/*"
      ]
    }
  ]
}
EOF
        
        aws iam put-role-policy \
            --role-name "$AGENT_ROLE_NAME" \
            --policy-name "SSMParameterAccess" \
            --policy-document file:///tmp/ssm-policy-$ACCOUNT_ID.json \
            2>/dev/null || true
        
        rm -f /tmp/ssm-policy-$ACCOUNT_ID.json
        
        log_info "  SSM permissions added"
    else
        log_warning "  Agent execution role not found (may be created by AgentCore)"
    fi
    
    log_success "Account $ACCOUNT_ID: Agent SSM parameters seeded"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    COUNTER=$((COUNTER + 1))
done

echo ""
log_success "=========================================="
log_success "Agent SSM Parameters Seeded!"
log_success "=========================================="
log_success "Successfully configured: $SUCCESS_COUNT/$ACCOUNT_COUNT accounts"
log_info ""
log_info "Parameters created by this script:"
log_info "  - /${STACK_PREFIX}/aws-region = $AWS_REGION"
log_info "  - /${STACK_PREFIX}/coveo/bedrock-model-id = $BEDROCK_MODEL"
log_info "  - /${STACK_PREFIX}/coveo/mcp-url = https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{encoded-arn}/invocations?qualifier=DEFAULT"
log_info ""
log_info "Parameters already created by Layer 3 CloudFormation:"
log_info "  - /${STACK_PREFIX}/coveo/runtime-arn = Agent Runtime ARN (Lambda uses this)"
log_info "  - /${STACK_PREFIX}/coveo/mcp-runtime-arn = MCP Runtime ARN (Agent uses this)"
log_info ""
log_info "Agent Runtime can now start successfully!"
