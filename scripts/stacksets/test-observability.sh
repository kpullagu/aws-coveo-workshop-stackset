#!/bin/bash
#
# Test Observability Implementation
# This script tests the observability features across Lambda, Agent Runtime, and MCP Runtime
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ASSUME_ROLE_NAME="${ASSUME_ROLE_NAME:-OrganizationAccountAccessRole}"

log_info "=========================================="
log_info "Test Observability Implementation"
log_info "=========================================="

# Get first account
ACCOUNT_ID=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id | [0]' \
    --output text)

log_info "Testing in Account: $ACCOUNT_ID"
echo ""

# Assume role
CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}" \
    --role-session-name "test-observability-${ACCOUNT_ID}" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')

# Find Lambda function
LAMBDA_NAME=$(aws lambda list-functions \
    --region "$AWS_REGION" \
    --query "Functions[?contains(FunctionName, 'agentcore-runtime')].FunctionName | [0]" \
    --output text)

if [ -z "$LAMBDA_NAME" ] || [ "$LAMBDA_NAME" == "None" ]; then
    log_error "Lambda function not found"
    exit 1
fi

log_info "Lambda Function: $LAMBDA_NAME"

# Generate test session ID
SESSION_ID="test-$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo $(date +%s))"
log_info "Test Session ID: $SESSION_ID"
echo ""

# Invoke Lambda with test payload
log_info "Invoking Lambda with test query..."
PAYLOAD=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "actor_id": "test-user",
  "text": "What is ACH payment?"
}
EOF
)

RESPONSE=$(aws lambda invoke \
    --region "$AWS_REGION" \
    --function-name "$LAMBDA_NAME" \
    --payload "$PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    /tmp/lambda-response.json 2>&1)

if [ $? -eq 0 ]; then
    log_success "✓ Lambda invoked successfully"
    cat /tmp/lambda-response.json | jq '.'
else
    log_error "Lambda invocation failed"
    echo "$RESPONSE"
    exit 1
fi

echo ""
log_info "Waiting 10 seconds for logs to propagate..."
sleep 10
echo ""

# Check CloudWatch Logs for observability markers
log_info "=========================================="
log_info "Checking CloudWatch Logs"
log_info "=========================================="

# Find Lambda log group
LAMBDA_LOG_GROUP="/aws/lambda/$LAMBDA_NAME"
log_info "Lambda Log Group: $LAMBDA_LOG_GROUP"

# Get recent log events with session ID
log_info "Searching for session ID: $SESSION_ID"
LAMBDA_LOGS=$(aws logs filter-log-events \
    --region "$AWS_REGION" \
    --log-group-name "$LAMBDA_LOG_GROUP" \
    --filter-pattern "$SESSION_ID" \
    --start-time $(($(date +%s) * 1000 - 300000)) \
    --query 'events[*].message' \
    --output text 2>/dev/null || echo "")

if [ -n "$LAMBDA_LOGS" ]; then
    log_success "✓ Found Lambda logs with session ID"
    echo "$LAMBDA_LOGS" | grep "OBSERVABILITY" || echo "No OBSERVABILITY markers found"
else
    log_warning "No Lambda logs found with session ID"
fi

echo ""

# Check Agent Runtime logs
AGENT_LOG_GROUP="/aws/bedrock-agentcore/agent-runtime"
log_info "Agent Runtime Log Group: $AGENT_LOG_GROUP"

AGENT_LOGS=$(aws logs filter-log-events \
    --region "$AWS_REGION" \
    --log-group-name "$AGENT_LOG_GROUP" \
    --filter-pattern "$SESSION_ID" \
    --start-time $(($(date +%s) * 1000 - 300000)) \
    --query 'events[*].message' \
    --output text 2>/dev/null || echo "")

if [ -n "$AGENT_LOGS" ]; then
    log_success "✓ Found Agent Runtime logs with session ID"
    echo "$AGENT_LOGS" | grep "OBSERVABILITY" || echo "No OBSERVABILITY markers found"
else
    log_warning "No Agent Runtime logs found with session ID"
fi

echo ""

# Check MCP Runtime logs
MCP_LOG_GROUP="/aws/bedrock-agentcore/mcp-runtime"
log_info "MCP Runtime Log Group: $MCP_LOG_GROUP"

MCP_LOGS=$(aws logs filter-log-events \
    --region "$AWS_REGION" \
    --log-group-name "$MCP_LOG_GROUP" \
    --filter-pattern "$SESSION_ID" \
    --start-time $(($(date +%s) * 1000 - 300000)) \
    --query 'events[*].message' \
    --output text 2>/dev/null || echo "")

if [ -n "$MCP_LOGS" ]; then
    log_success "✓ Found MCP Runtime logs with session ID"
    echo "$MCP_LOGS" | grep "OBSERVABILITY" || echo "No OBSERVABILITY markers found"
else
    log_warning "No MCP Runtime logs found with session ID"
fi

echo ""

# Check X-Ray traces
log_info "=========================================="
log_info "Checking X-Ray Traces"
log_info "=========================================="

# Wait a bit more for X-Ray to process
log_info "Waiting 20 seconds for X-Ray traces to process..."
sleep 20

# Search for traces with session ID
TRACES=$(aws xray get-trace-summaries \
    --region "$AWS_REGION" \
    --start-time $(date -u -d '5 minutes ago' +%s 2>/dev/null || date -u -v-5M +%s 2>/dev/null || echo $(($(date +%s) - 300))) \
    --end-time $(date -u +%s) \
    --filter-expression "annotation.session_id = \"$SESSION_ID\"" \
    --query 'TraceSummaries[*].[Id,Duration,ResponseTime]' \
    --output text 2>/dev/null || echo "")

if [ -n "$TRACES" ]; then
    log_success "✓ Found X-Ray traces with session ID"
    echo "$TRACES"
else
    log_warning "No X-Ray traces found with session ID (may take longer to appear)"
fi

echo ""

# Check Bedrock Model Invocation Logs
log_info "=========================================="
log_info "Checking Bedrock Model Invocation Logs"
log_info "=========================================="

BEDROCK_LOG_GROUP=$(aws logs describe-log-groups \
    --region "$AWS_REGION" \
    --log-group-name-prefix "/aws/bedrock/modelinvocations/" \
    --query "logGroups[0].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$BEDROCK_LOG_GROUP" ] && [ "$BEDROCK_LOG_GROUP" != "None" ]; then
    log_info "Bedrock Log Group: $BEDROCK_LOG_GROUP"
    
    BEDROCK_LOGS=$(aws logs filter-log-events \
        --region "$AWS_REGION" \
        --log-group-name "$BEDROCK_LOG_GROUP" \
        --start-time $(($(date +%s) * 1000 - 300000)) \
        --query 'events[0].message' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$BEDROCK_LOGS" ] && [ "$BEDROCK_LOGS" != "None" ]; then
        log_success "✓ Found Bedrock model invocation logs"
        echo "$BEDROCK_LOGS" | jq '.' 2>/dev/null || echo "$BEDROCK_LOGS"
    else
        log_warning "No recent Bedrock logs found"
    fi
else
    log_warning "Bedrock model invocation log group not found"
fi

echo ""
log_success "=========================================="
log_success "Observability Test Complete!"
log_success "=========================================="
log_info ""
log_info "Summary:"
log_info "  Session ID: $SESSION_ID"
log_info "  Lambda Logs: $([ -n "$LAMBDA_LOGS" ] && echo "✓ Found" || echo "✗ Not found")"
log_info "  Agent Logs: $([ -n "$AGENT_LOGS" ] && echo "✓ Found" || echo "✗ Not found")"
log_info "  MCP Logs: $([ -n "$MCP_LOGS" ] && echo "✓ Found" || echo "✗ Not found")"
log_info "  X-Ray Traces: $([ -n "$TRACES" ] && echo "✓ Found" || echo "✗ Not found")"
log_info "  Bedrock Logs: $([ -n "$BEDROCK_LOGS" ] && echo "✓ Found" || echo "✗ Not found")"
log_info ""
log_info "To view logs in CloudWatch Logs Insights, use:"
log_info "  fields @timestamp, @message"
log_info "  | filter @message like /$SESSION_ID/"
log_info "  | sort @timestamp desc"
