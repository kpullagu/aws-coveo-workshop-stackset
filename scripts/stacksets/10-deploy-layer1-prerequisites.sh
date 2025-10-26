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
