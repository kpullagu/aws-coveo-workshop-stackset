#!/bin/bash
#
# Deploy StackSet Layer 1: Prerequisites (S3, ECR)
#

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=========================================="
log_info "Deploying Layer 1: Prerequisites"
log_info "=========================================="
log_info "StackSet: workshop-layer1-prerequisites"
log_info "Target OU: $OU_ID"
log_info "Region: $AWS_REGION"
echo ""

# Create StackSet
log_info "Creating StackSet..."
aws cloudformation create-stack-set \
    --stack-set-name workshop-layer1-prerequisites \
    --template-body file://cfn/stacksets/stackset-1-prerequisites.yml \
    --parameters \
        ParameterKey=StackPrefix,ParameterValue=$STACK_PREFIX \
        ParameterKey=MasterAccountId,ParameterValue=$MASTER_ACCOUNT_ID \
        ParameterKey=Environment,ParameterValue=workshop \
    --permission-model SERVICE_MANAGED \
    --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$AWS_REGION" 2>/dev/null || log_info "StackSet already exists, updating..."

# Update StackSet if it already exists
aws cloudformation update-stack-set \
    --stack-set-name workshop-layer1-prerequisites \
    --template-body file://cfn/stacksets/stackset-1-prerequisites.yml \
    --parameters \
        ParameterKey=StackPrefix,ParameterValue=$STACK_PREFIX \
        ParameterKey=MasterAccountId,ParameterValue=$MASTER_ACCOUNT_ID \
        ParameterKey=Environment,ParameterValue=workshop \
    --permission-model SERVICE_MANAGED \
    --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$AWS_REGION" 2>/dev/null || true

log_success "StackSet created/updated"

# Deploy to OU
log_info "Deploying stack instances to OU..."
OPERATION_ID=$(aws cloudformation create-stack-instances \
    --stack-set-name workshop-layer1-prerequisites \
    --deployment-targets OrganizationalUnitIds=$OU_ID \
    --regions $AWS_REGION \
    --operation-preferences \
        FailureToleranceCount=$FAILURE_TOLERANCE_COUNT,MaxConcurrentCount=$MAX_CONCURRENT_ACCOUNTS \
    --region "$AWS_REGION" \
    --query 'OperationId' \
    --output text 2>/dev/null || echo "")

if [ -n "$OPERATION_ID" ]; then
    log_success "Stack instances deployment started"
    log_info "Operation ID: $OPERATION_ID"
    
    # Wait for operation to complete
    log_info "Waiting for deployment to complete (this may take 5-10 minutes)..."
    aws cloudformation wait stack-set-operation-complete \
        --stack-set-name workshop-layer1-prerequisites \
        --operation-id "$OPERATION_ID" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    log_success "Layer 1 deployment complete!"
else
    log_info "No new stack instances to create"
fi

# Wait for instances to stabilize and fix any OUTDATED instances
echo ""
log_info "Waiting for stack instances to stabilize..."
sleep 30

# Check for OUTDATED instances and fix them
log_info "Checking for OUTDATED instances..."
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    OUTDATED_ACCOUNTS=$(aws cloudformation list-stack-instances \
        --stack-set-name workshop-layer1-prerequisites \
        --region "$AWS_REGION" \
        --query 'Summaries[?Status==`OUTDATED`].Account' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$OUTDATED_ACCOUNTS" ]; then
        log_success "All instances are CURRENT"
        break
    fi
    
    log_warning "Found OUTDATED accounts: $OUTDATED_ACCOUNTS"
    log_info "Updating OUTDATED instances (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    
    # Convert space-separated accounts to array for proper AWS CLI handling
    ACCOUNT_ARRAY=($OUTDATED_ACCOUNTS)
    
    log_info "Updating ${#ACCOUNT_ARRAY[@]} accounts with MaxConcurrentCount=${MAX_CONCURRENT_ACCOUNTS}"
    
    UPDATE_OP_ID=$(aws cloudformation update-stack-instances \
        --stack-set-name workshop-layer1-prerequisites \
        --accounts "${ACCOUNT_ARRAY[@]}" \
        --regions $AWS_REGION \
        --operation-preferences \
            FailureToleranceCount=${FAILURE_TOLERANCE_COUNT},MaxConcurrentCount=${MAX_CONCURRENT_ACCOUNTS} \
        --region "$AWS_REGION" \
        --query 'OperationId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$UPDATE_OP_ID" ]; then
        log_info "Update operation started: $UPDATE_OP_ID"
        log_info "Waiting for update to complete (this may take 5-10 minutes)..."
        
        # Manual polling loop with better visibility
        local WAIT_COUNT=0
        local MAX_WAIT=60  # 30 minutes (60 * 30 seconds)
        
        while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
            local OP_STATUS=$(aws cloudformation describe-stack-set-operation \
                --stack-set-name workshop-layer1-prerequisites \
                --operation-id "$UPDATE_OP_ID" \
                --region "$AWS_REGION" \
                --query 'StackSetOperation.Status' \
                --output text 2>/dev/null || echo "UNKNOWN")
            
            if [ "$OP_STATUS" = "SUCCEEDED" ]; then
                log_success "✓ Update operation completed successfully"
                break
            elif [ "$OP_STATUS" = "FAILED" ] || [ "$OP_STATUS" = "STOPPED" ]; then
                log_error "✗ Update operation failed with status: $OP_STATUS"
                break
            else
                log_info "  Status: $OP_STATUS (waited $((WAIT_COUNT * 30))s)"
                sleep 30
                ((WAIT_COUNT++))
            fi
        done
        
        if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
            log_warning "⚠️  Update operation timeout after $((MAX_WAIT * 30))s"
            log_warning "Operation may still be running in background"
        fi
        
        sleep 10
    else
        log_error "✗ Failed to start update operation"
    fi
    
    ((RETRY_COUNT++))
done

# Final status check
FINAL_OUTDATED=$(aws cloudformation list-stack-instances \
    --stack-set-name workshop-layer1-prerequisites \
    --region "$AWS_REGION" \
    --query 'Summaries[?Status==`OUTDATED`].Account' \
    --output text 2>/dev/null || echo "")

if [ -n "$FINAL_OUTDATED" ]; then
    log_warning "Some instances are still OUTDATED: $FINAL_OUTDATED"
    log_warning "This may resolve automatically. Continuing..."
fi

# Show status
echo ""
log_info "Checking deployment status..."
aws cloudformation list-stack-instances \
    --stack-set-name workshop-layer1-prerequisites \
    --region "$AWS_REGION" \
    --query 'Summaries[*].[Account,Status]' \
    --output table

echo ""
log_success "Layer 1 (Prerequisites) deployed successfully!"
