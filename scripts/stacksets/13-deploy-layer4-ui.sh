#!/bin/bash
#
# Deploy StackSet Layer 4: UI (ECS Express)
#

# Note: Not using 'set -e' to allow better error handling

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=========================================="
log_info "Deploying Layer 4: UI (ECS Express)"
log_info "=========================================="
log_info "StackSet: workshop-layer4-ui"
log_info "Target OU: $OU_ID"
log_info "Region: $AWS_REGION"
echo ""

UI_IMAGE_DIGEST=${UI_IMAGE_DIGEST:-$(aws ecr describe-images \
    --repository-name "${STACK_PREFIX}-ui-master" \
    --image-ids imageTag="$UI_IMAGE_TAG" \
    --region "$AWS_REGION" \
    --query 'imageDetails[0].imageDigest' \
    --output text 2>/dev/null || echo "latest")}

log_info "UI image digest: $UI_IMAGE_DIGEST"

poll_operation() {
    local operation_id="$1"
    local label="$2"

    if [ -z "$operation_id" ]; then
        return 0
    fi

    log_info "Waiting for $label operation to complete..."
    for _ in {1..90}; do
        local status
        status=$(aws cloudformation describe-stack-set-operation \
            --stack-set-name workshop-layer4-ui \
            --operation-id "$operation_id" \
            --region "$AWS_REGION" \
            --query 'StackSetOperation.Status' \
            --output text 2>/dev/null || echo "UNKNOWN")

        log_info "$label status: $status"
        case "$status" in
            SUCCEEDED)
                return 0
                ;;
            FAILED|STOPPED)
                log_error "$label operation failed with status: $status"
                return 1
                ;;
        esac
        sleep 10
    done

    log_error "$label operation did not complete in time"
    return 1
}

STACKSET_UPDATED=false

# Check if StackSet exists
if aws cloudformation describe-stack-set \
    --stack-set-name workshop-layer4-ui \
    --region "$AWS_REGION" >/dev/null 2>&1; then
    
    log_info "StackSet exists, updating..."
    UPDATE_OPERATION_ID=$(aws cloudformation update-stack-set \
        --stack-set-name workshop-layer4-ui \
        --template-body file://cfn/stacksets/stackset-4-ui.yml \
        --parameters \
            ParameterKey=StackPrefix,ParameterValue=$STACK_PREFIX \
            ParameterKey=Environment,ParameterValue=workshop \
            ParameterKey=MasterAccountId,ParameterValue=$MASTER_ACCOUNT_ID \
            ParameterKey=UiCpu,ParameterValue=$UI_CPU \
            ParameterKey=UiMemory,ParameterValue=$UI_MEMORY \
            ParameterKey=UiContainerPort,ParameterValue=$UI_CONTAINER_PORT \
            ParameterKey=UiHealthCheckPath,ParameterValue=$UI_HEALTH_CHECK_PATH \
            ParameterKey=UiImageTag,ParameterValue=$UI_IMAGE_TAG \
            ParameterKey=UiImageDigest,ParameterValue=$UI_IMAGE_DIGEST \
        --permission-model SERVICE_MANAGED \
        --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --query 'OperationId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$UPDATE_OPERATION_ID" ]; then
        STACKSET_UPDATED=true
        log_success "StackSet update started"
        log_info "Operation ID: $UPDATE_OPERATION_ID"
        poll_operation "$UPDATE_OPERATION_ID" "StackSet template update" || exit 1
    else
        log_warning "No StackSet template changes to update"
    fi
else
    log_info "Creating new StackSet..."
    aws cloudformation create-stack-set \
        --stack-set-name workshop-layer4-ui \
        --template-body file://cfn/stacksets/stackset-4-ui.yml \
        --parameters \
            ParameterKey=StackPrefix,ParameterValue=$STACK_PREFIX \
            ParameterKey=Environment,ParameterValue=workshop \
            ParameterKey=MasterAccountId,ParameterValue=$MASTER_ACCOUNT_ID \
            ParameterKey=UiCpu,ParameterValue=$UI_CPU \
            ParameterKey=UiMemory,ParameterValue=$UI_MEMORY \
            ParameterKey=UiContainerPort,ParameterValue=$UI_CONTAINER_PORT \
            ParameterKey=UiHealthCheckPath,ParameterValue=$UI_HEALTH_CHECK_PATH \
            ParameterKey=UiImageTag,ParameterValue=$UI_IMAGE_TAG \
            ParameterKey=UiImageDigest,ParameterValue=$UI_IMAGE_DIGEST \
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
    
    poll_operation "$OPERATION_ID" "Stack instance create" || exit 1
    log_success "Layer 4 deployment complete!"
else
    log_info "No new stack instances to create"
fi

if [ "$STACKSET_UPDATED" = true ]; then
    log_info "Applying updated StackSet template to existing stack instances..."
    INSTANCE_UPDATE_OPERATION_ID=$(aws cloudformation update-stack-instances \
        --stack-set-name workshop-layer4-ui \
        --deployment-targets OrganizationalUnitIds=$OU_ID \
        --regions $AWS_REGION \
        --operation-preferences \
            FailureToleranceCount=$FAILURE_TOLERANCE_COUNT,MaxConcurrentCount=$MAX_CONCURRENT_ACCOUNTS \
        --region "$AWS_REGION" \
        --query 'OperationId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$INSTANCE_UPDATE_OPERATION_ID" ]; then
        log_success "Stack instances update started"
        log_info "Operation ID: $INSTANCE_UPDATE_OPERATION_ID"
        poll_operation "$INSTANCE_UPDATE_OPERATION_ID" "Stack instance update" || exit 1
    else
        log_info "No existing stack instances required an update"
    fi
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
