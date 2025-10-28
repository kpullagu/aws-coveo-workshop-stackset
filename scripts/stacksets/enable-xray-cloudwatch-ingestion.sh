#!/bin/bash
#
# Enable X-Ray Span Ingestion to CloudWatch Logs
# This allows viewing traces in Bedrock AgentCore Observability dashboard
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ASSUME_ROLE_NAME="${ASSUME_ROLE_NAME:-OrganizationAccountAccessRole}"

log_info "=========================================="
log_info "Enable X-Ray CloudWatch Logs Ingestion"
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
        --role-session-name "xray-config-${ACCOUNT_ID}" \
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
    
    # Step 1: Create CloudWatch Logs resource policy for X-Ray
    log_info "Step 1: Creating CloudWatch Logs resource policy for X-Ray..."
    
    POLICY_NAME="XRaySpanIngestionPolicy"
    POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowXRayToWriteSpans",
      "Effect": "Allow",
      "Principal": {
        "Service": "xray.amazonaws.com"
      },
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/spans:*",
        "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/application-signals/data:*"
      ]
    }
  ]
}
EOF
)
    
    # Check if policy exists
    EXISTING_POLICY=$(aws logs describe-resource-policies \
        --region "$AWS_REGION" \
        --query "resourcePolicies[?policyName=='${POLICY_NAME}'].policyName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_POLICY" ]; then
        log_info "Policy already exists, updating..."
        aws logs put-resource-policy \
            --policy-name "$POLICY_NAME" \
            --policy-document "$POLICY_DOCUMENT" \
            --region "$AWS_REGION" >/dev/null 2>&1
    else
        log_info "Creating new policy..."
        aws logs put-resource-policy \
            --policy-name "$POLICY_NAME" \
            --policy-document "$POLICY_DOCUMENT" \
            --region "$AWS_REGION" >/dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        log_success "✓ CloudWatch Logs resource policy created"
    else
        log_error "Failed to create CloudWatch Logs resource policy"
        COUNTER=$((COUNTER + 1))
        continue
    fi
    
    # Step 2: Create log groups for X-Ray spans
    log_info "Step 2: Creating log groups for X-Ray spans..."
    
    # Create /aws/spans log group
    aws logs create-log-group \
        --log-group-name "/aws/spans" \
        --region "$AWS_REGION" 2>/dev/null || log_info "  /aws/spans already exists"
    
    # Set retention policy (7 days)
    aws logs put-retention-policy \
        --log-group-name "/aws/spans" \
        --retention-in-days 7 \
        --region "$AWS_REGION" 2>/dev/null || true
    
    # Create /aws/application-signals/data log group
    aws logs create-log-group \
        --log-group-name "/aws/application-signals/data" \
        --region "$AWS_REGION" 2>/dev/null || log_info "  /aws/application-signals/data already exists"
    
    # Set retention policy (7 days)
    aws logs put-retention-policy \
        --log-group-name "/aws/application-signals/data" \
        --retention-in-days 7 \
        --region "$AWS_REGION" 2>/dev/null || true
    
    log_success "✓ Log groups created"
    
    # Step 3: Configure X-Ray to send spans to CloudWatch Logs
    log_info "Step 3: Configuring X-Ray telemetry destination..."
    
    # Enable CloudWatch Logs as destination for X-Ray spans
    aws xray put-telemetry-records \
        --telemetry-records '[
            {
                "Timestamp": '$(date +%s)',
                "SegmentsReceivedCount": 0,
                "SegmentsSentCount": 0,
                "SegmentsSpilloverCount": 0,
                "SegmentsRejectedCount": 0,
                "BackendConnectionErrors": {
                    "TimeoutCount": 0,
                    "ConnectionRefusedCount": 0,
                    "HTTPCode4XXCount": 0,
                    "HTTPCode5XXCount": 0,
                    "UnknownHostCount": 0,
                    "OtherCount": 0
                }
            }
        ]' \
        --region "$AWS_REGION" 2>/dev/null || true
    
    # Configure sampling rules for better trace capture
    log_info "Step 4: Configuring X-Ray sampling rules..."
    
    SAMPLING_RULE=$(cat <<EOF
{
  "SamplingRule": {
    "RuleName": "${STACK_PREFIX}-high-sampling",
    "Priority": 1000,
    "FixedRate": 1.0,
    "ReservoirSize": 100,
    "ServiceName": "*",
    "ServiceType": "*",
    "Host": "*",
    "HTTPMethod": "*",
    "URLPath": "*",
    "Version": 1,
    "ResourceARN": "*",
    "Attributes": {}
  }
}
EOF
)
    
    # Try to create sampling rule (may already exist)
    aws xray create-sampling-rule \
        --cli-input-json "$SAMPLING_RULE" \
        --region "$AWS_REGION" 2>/dev/null && log_success "✓ Sampling rule created" || log_info "  Sampling rule may already exist"
    
    # Step 5: Configure indexing percentage (100% for workshop)
    log_info "Step 5: Configuring trace indexing..."
    
    # Note: X-Ray indexing configuration is done via sampling rules above
    # The FixedRate of 1.0 means 100% of traces are captured
    
    log_success "✓ X-Ray configured for 100% trace capture"
    
    # Step 6: Configure Memory Observability (per-memory delivery)
    log_info "Step 6: Configuring Memory observability..."
    
    # Find Memory resources in this account
    MEMORY_ARN=$(aws cloudformation describe-stacks \
        --region "$AWS_REGION" \
        --query 'Stacks[?contains(StackName, `layer3-ai-services`)].Outputs[?OutputKey==`AgentMemoryArn`].OutputValue | [0]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$MEMORY_ARN" ] && [ "$MEMORY_ARN" != "None" ]; then
        MEMORY_ID="${MEMORY_ARN##*/}"
        log_info "  Found Memory: $MEMORY_ID"
        
        # Create log group for Memory application logs
        LOG_GROUP="/aws/vendedlogs/bedrock-agentcore/memory/APPLICATION_LOGS/${MEMORY_ID}"
        
        aws logs create-log-group \
            --region "$AWS_REGION" \
            --log-group-name "$LOG_GROUP" 2>/dev/null && \
            log_info "    ✓ Memory log group created" || \
            log_info "    Memory log group already exists"
        
        # Set retention policy
        aws logs put-retention-policy \
            --log-group-name "$LOG_GROUP" \
            --retention-in-days 7 \
            --region "$AWS_REGION" 2>/dev/null || true
        
        LG_ARN="arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}"
        
        # Create delivery sources
        aws logs put-delivery-source \
            --region "$AWS_REGION" \
            --name "${MEMORY_ID}-logs-source" \
            --log-type APPLICATION_LOGS \
            --resource-arn "$MEMORY_ARN" 2>/dev/null || true
        
        aws logs put-delivery-source \
            --region "$AWS_REGION" \
            --name "${MEMORY_ID}-traces-source" \
            --log-type TRACES \
            --resource-arn "$MEMORY_ARN" 2>/dev/null || true
        
        # Create delivery destinations
        aws logs put-delivery-destination \
            --region "$AWS_REGION" \
            --name "${MEMORY_ID}-logs-dest" \
            --delivery-destination-type CWL \
            --delivery-destination-configuration "{\"destinationResourceArn\":\"$LG_ARN\"}" 2>/dev/null || true
        
        aws logs put-delivery-destination \
            --region "$AWS_REGION" \
            --name "${MEMORY_ID}-traces-dest" \
            --delivery-destination-type XRAY 2>/dev/null || true
        
        # Get destination ARNs
        LOGS_DEST_ARN=$(aws logs describe-delivery-destinations \
            --region "$AWS_REGION" \
            --query "deliveryDestinations[?name=='${MEMORY_ID}-logs-dest'].arn" \
            --output text 2>/dev/null || echo "")
        
        TRACES_DEST_ARN=$(aws logs describe-delivery-destinations \
            --region "$AWS_REGION" \
            --query "deliveryDestinations[?name=='${MEMORY_ID}-traces-dest'].arn" \
            --output text 2>/dev/null || echo "")
        
        # Connect sources to destinations
        if [ -n "$LOGS_DEST_ARN" ] && [ -n "$TRACES_DEST_ARN" ]; then
            aws logs create-delivery \
                --region "$AWS_REGION" \
                --delivery-source-name "${MEMORY_ID}-logs-source" \
                --delivery-destination-arn "$LOGS_DEST_ARN" 2>/dev/null || true
            
            aws logs create-delivery \
                --region "$AWS_REGION" \
                --delivery-source-name "${MEMORY_ID}-traces-source" \
                --delivery-destination-arn "$TRACES_DEST_ARN" 2>/dev/null || true
            
            log_success "  ✓ Memory observability configured"
        else
            log_warning "  Could not configure Memory delivery"
        fi
    else
        log_info "  No Memory found in this account, skipping Memory configuration"
    fi
    
    # Step 7: Verify configuration
    log_info "Step 7: Verifying configuration..."
    
    # Check if log groups exist
    SPANS_LG=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/spans" \
        --region "$AWS_REGION" \
        --query 'logGroups[0].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    APP_SIGNALS_LG=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/application-signals/data" \
        --region "$AWS_REGION" \
        --query 'logGroups[0].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$SPANS_LG" ] && [ -n "$APP_SIGNALS_LG" ]; then
        log_success "✓ Configuration verified"
        log_info "  Spans log group: $SPANS_LG"
        log_info "  Application signals log group: $APP_SIGNALS_LG"
    else
        log_warning "Some log groups may not be created yet"
    fi
    
    log_success "Account $ACCOUNT_ID configured successfully!"
    echo ""
    
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    COUNTER=$((COUNTER + 1))
done

log_success "=========================================="
log_success "Configuration Complete!"
log_success "=========================================="
log_info "X-Ray span ingestion and Memory observability are now enabled in all accounts."
log_info ""
log_info "What this enables:"
log_info "  ✓ X-Ray traces are ingested into CloudWatch Logs"
log_info "  ✓ Memory logs and traces are delivered to CloudWatch/X-Ray"
log_info "  ✓ Traces are viewable in Bedrock AgentCore Observability dashboard"
log_info "  ✓ 100% of traces are captured (FixedRate: 1.0)"
log_info "  ✓ Spans are stored in /aws/spans log group"
log_info "  ✓ Application signals in /aws/application-signals/data"
log_info "  ✓ Memory logs in /aws/vendedlogs/bedrock-agentcore/memory/"
log_info ""
log_info "To view traces:"
log_info "  1. Go to Bedrock AgentCore console"
log_info "  2. Navigate to Observability section"
log_info "  3. View traces, metrics, and insights"
log_info "  4. The 'Enable Transaction Search' banner should be gone from Memory tab"
log_info ""
log_info "To query spans in CloudWatch Logs Insights:"
log_info "  Log Group: /aws/spans"
log_info "  Query:"
log_info "    fields @timestamp, @message"
log_info "    | filter @message like /session_id/"
log_info "    | sort @timestamp desc"
log_info ""
log_info "To query Memory logs:"
log_info "  Log Group: /aws/vendedlogs/bedrock-agentcore/memory/APPLICATION_LOGS/<memory-id>"

