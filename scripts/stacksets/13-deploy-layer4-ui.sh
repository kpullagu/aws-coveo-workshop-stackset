#!/bin/bash
#
# Deploy StackSet Layer 4: UI (App Runner)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=========================================="
log_info "Deploying Layer 4: UI (App Runner)"
log_info "=========================================="
log_info "StackSet: workshop-layer4-ui"
log_info "Target OU: $OU_ID"
log_info "Region: $AWS_REGION"
echo ""

# Check if StackSet exists
if aws cloudformation describe-stack-set \
    --stack-set-name workshop-layer4-ui \
    --region "$AWS_REGION" >/dev/null 2>&1; then
    
    log_info "StackSet exists, updating..."
    aws cloudformation update-stack-set \
        --stack-set-name workshop-layer4-ui \
        --template-body file://cfn/stacksets/stackset-4-ui.yml \
        --parameters \
            ParameterKey=StackPrefix,ParameterValue=$STACK_PREFIX \
            ParameterKey=Environment,ParameterValue=workshop \
            ParameterKey=MasterAccountId,ParameterValue=$MASTER_ACCOUNT_ID \
        --permission-model SERVICE_MANAGED \
        --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" 2>/dev/null || log_warning "No changes to update"
    
    log_success "StackSet updated"
else
    log_info "Creating new StackSet..."
    aws cloudformation create-stack-set \
        --stack-set-name workshop-layer4-ui \
        --template-body file://cfn/stacksets/stackset-4-ui.yml \
        --parameters \
            ParameterKey=StackPrefix,ParameterValue=$STACK_PREFIX \
            ParameterKey=Environment,ParameterValue=workshop \
            ParameterKey=MasterAccountId,ParameterValue=$MASTER_ACCOUNT_ID \
        --permission-model SERVICE_MANAGED \
        --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION"
    
    log_success "StackSet created"
fi

# Deploy to OU
log_info "Deploying stack instances to OU..."
OPERATION_ID=$(aws cloudformation create-stack-instances \
    --stack-set-name workshop-layer4-ui \
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
    log_info "Waiting for deployment to complete (this may take 10-15 minutes)..."
    aws cloudformation wait stack-set-operation-complete \
        --stack-set-name workshop-layer4-ui \
        --operation-id "$OPERATION_ID" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    log_success "Layer 4 deployment complete!"
else
    log_info "No new stack instances to create"
fi

# Show status
echo ""
log_info "Checking deployment status..."
aws cloudformation list-stack-instances \
    --stack-set-name workshop-layer4-ui \
    --region "$AWS_REGION" \
    --query 'Summaries[*].[Account,Status]' \
    --output table

echo ""
log_success "Layer 4 (UI) deployed successfully!"
