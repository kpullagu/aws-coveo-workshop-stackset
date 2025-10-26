#!/bin/bash
#
# Destroy all StackSets - Version 2 (More Reliable)
# This script properly waits for operations to complete
#

set -e -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ASSUME_ROLE_NAME="${ASSUME_ROLE_NAME:-OrganizationAccountAccessRole}"

log_info "=========================================="
log_info "DESTROYING ALL STACKSETS - V2"
log_info "=========================================="
log_warning "This will delete ALL workshop resources!"
log_warning "Press Ctrl+C within 10 seconds to cancel..."
sleep 10

# Get list of accounts
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

ACCOUNT_ARRAY=($ACCOUNT_IDS)
log_info "Found ${#ACCOUNT_ARRAY[@]} accounts:"
for ACC in ${ACCOUNT_ARRAY[@]}; do
    log_info "  - $ACC"
done

# Define StackSets in reverse order (Layer 4 -> Layer 1)
STACKSETS=(
    "${STACK_PREFIX}-layer4-ui"
    "${STACK_PREFIX}-layer3-ai-services"
    "${STACK_PREFIX}-layer2-core"
    "${STACK_PREFIX}-layer1-prerequisites"
    "${STACK_PREFIX}-lambda-copy"
)

# Function to delete stack instances and wait
delete_instances_and_wait() {
    local stackset_name=$1
    
    log_info "=========================================="
    log_info "Processing StackSet: $stackset_name"
    log_info "=========================================="
    
    # Check if StackSet exists
    if ! aws cloudformation describe-stack-set \
        --stack-set-name "$stackset_name" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "StackSet does not exist, skipping"
        return 0
    fi
    
    # Get current instances
    INSTANCES=$(aws cloudformation list-stack-instances \
        --stack-set-name "$stackset_name" \
        --region "$AWS_REGION" \
        --query 'Summaries[?Status!=`DELETED`]' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$INSTANCES" == "[]" ]; then
        log_info "No instances to delete"
    else
        log_info "Found instances:"
        echo "$INSTANCES" | jq -r '.[] | "  \(.Account) - \(.Region) - \(.Status)"'
        
        # Get unique regions
        REGIONS=$(echo "$INSTANCES" | jq -r '.[].Region' | sort -u)
        REGION_LIST=$(echo $REGIONS | tr '\n' ' ')
        
        log_info "Initiating delete operation..."
        log_info "  Deployment Target: OU ($OU_ID)"
        log_info "  Regions: $REGION_LIST"
        
        # Start delete operation (disable set -e temporarily)
        # For SERVICE_MANAGED StackSets, use --deployment-targets with OrganizationalUnitIds
        set +e
        OPERATION_OUTPUT=$(aws cloudformation delete-stack-instances \
            --stack-set-name "$stackset_name" \
            --deployment-targets OrganizationalUnitIds="$OU_ID" \
            --regions $REGION_LIST \
            --no-retain-stacks \
            --region "$AWS_REGION" \
            --output json 2>&1)
        DELETE_EXIT_CODE=$?
        set -e
        
        if [ $DELETE_EXIT_CODE -ne 0 ]; then
            log_error "Failed to start delete operation:"
            echo "$OPERATION_OUTPUT"
            return 1
        fi
        
        OPERATION_ID=$(echo "$OPERATION_OUTPUT" | jq -r '.OperationId' 2>/dev/null || echo "")
        
        if [ -z "$OPERATION_ID" ] || [ "$OPERATION_ID" == "null" ]; then
            log_error "No operation ID returned"
            echo "$OPERATION_OUTPUT"
            return 1
        fi
        
        log_success "Operation started: $OPERATION_ID"
        
        # Wait for operation to complete (up to 30 minutes)
        log_info "Waiting for operation to complete (this may take several minutes)..."
        WAIT_COUNT=0
        MAX_WAIT=180  # 30 minutes
        
        while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
            OP_STATUS=$(aws cloudformation describe-stack-set-operation \
                --stack-set-name "$stackset_name" \
                --operation-id "$OPERATION_ID" \
                --region "$AWS_REGION" \
                --query 'StackSetOperation.Status' \
                --output text 2>/dev/null || echo "UNKNOWN")
            
            if [ "$OP_STATUS" == "SUCCEEDED" ]; then
                log_success "✓ Operation completed successfully"
                break
            elif [ "$OP_STATUS" == "FAILED" ]; then
                log_error "✗ Operation failed"
                
                # Show failure details
                log_info "Fetching failure details..."
                FAILURE_DETAILS=$(aws cloudformation describe-stack-set-operation \
                    --stack-set-name "$stackset_name" \
                    --operation-id "$OPERATION_ID" \
                    --region "$AWS_REGION" \
                    --output json 2>/dev/null || echo "{}")
                
                echo "$FAILURE_DETAILS" | jq -r '.StackSetOperation | "Status: \(.Status)\nStatusReason: \(.StatusReason // "N/A")"'
                
                # Show per-instance failures
                log_info "Checking individual stack instance failures..."
                INSTANCE_SUMMARIES=$(aws cloudformation list-stack-set-operation-results \
                    --stack-set-name "$stackset_name" \
                    --operation-id "$OPERATION_ID" \
                    --region "$AWS_REGION" \
                    --query 'Summaries[?Status==`FAILED`]' \
                    --output json 2>/dev/null || echo "[]")
                
                if [ "$INSTANCE_SUMMARIES" != "[]" ]; then
                    echo "$INSTANCE_SUMMARIES" | jq -r '.[] | "Account: \(.Account), Region: \(.Region)\nReason: \(.StatusReason // "N/A")\n"'
                fi
                
                log_warning "Continuing despite failure..."
                break
            elif [ "$OP_STATUS" == "STOPPED" ]; then
                log_warning "Operation was stopped"
                return 1
            fi
            
            # Progress update every 30 seconds
            if [ $((WAIT_COUNT % 3)) -eq 0 ]; then
                ELAPSED=$((WAIT_COUNT * 10))
                log_info "  Status: $OP_STATUS (${ELAPSED}s elapsed)"
            fi
            
            sleep 10
            WAIT_COUNT=$((WAIT_COUNT + 1))
        done
        
        if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
            log_error "Timeout waiting for operation to complete"
            return 1
        fi
    fi
    
    # Verify all instances are deleted before removing StackSet
    FINAL_INSTANCES=$(aws cloudformation list-stack-instances \
        --stack-set-name "$stackset_name" \
        --region "$AWS_REGION" \
        --query 'Summaries[?Status!=`DELETED`]' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$FINAL_INSTANCES" != "[]" ]; then
        log_warning "Some instances still exist, attempting manual cleanup..."
        echo "$FINAL_INSTANCES" | jq -r '.[] | "  \(.Account) - \(.Region) - \(.Status)"'
        
        # Try to delete remaining instances directly in child accounts
        REMAINING_ACCOUNTS=$(echo "$FINAL_INSTANCES" | jq -r '.[].Account' | sort -u)
        
        for ACCOUNT_ID in $REMAINING_ACCOUNTS; do
            log_info "Cleaning up account: $ACCOUNT_ID"
            
            CREDS=$(aws sts assume-role \
                --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}" \
                --role-session-name "cleanup-${ACCOUNT_ID}" \
                --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$CREDS" ]; then
                export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
                export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
                export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
                
                # Find and delete stacks
                STACKS=$(aws cloudformation list-stacks \
                    --region "$AWS_REGION" \
                    --query "StackSummaries[?contains(StackName, 'StackSet-${stackset_name}') && StackStatus!='DELETE_COMPLETE'].StackName" \
                    --output text 2>/dev/null || echo "")
                
                for STACK in $STACKS; do
                    log_info "  Deleting stack: $STACK"
                    aws cloudformation delete-stack \
                        --stack-name "$STACK" \
                        --region "$AWS_REGION" 2>/dev/null || true
                done
                
                unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
            fi
        done
        
        log_info "Waiting 30 seconds for manual cleanup..."
        sleep 30
    fi
    
    # Delete the StackSet itself
    log_info "Deleting StackSet..."
    set +e
    DELETE_OUTPUT=$(aws cloudformation delete-stack-set \
        --stack-set-name "$stackset_name" \
        --region "$AWS_REGION" 2>&1)
    DELETE_CODE=$?
    set -e
    
    if [ $DELETE_CODE -eq 0 ]; then
        log_success "✓ StackSet deleted"
        return 0
    else
        log_warning "Failed to delete StackSet: $DELETE_OUTPUT"
        log_info "Continuing anyway..."
        return 0
    fi
}

# Process each StackSet
for STACKSET in "${STACKSETS[@]}"; do
    delete_instances_and_wait "$STACKSET"
    echo ""
done

# Clean up resources in child accounts
log_info "=========================================="
log_info "Cleaning Up Resources in Child Accounts"
log_info "=========================================="

for ACCOUNT_ID in ${ACCOUNT_ARRAY[@]}; do
    log_info "Cleaning account: $ACCOUNT_ID"
    
    # Assume role
    CREDS=$(aws sts assume-role \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}" \
        --role-session-name "cleanup-${ACCOUNT_ID}" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_warning "Cannot assume role in account $ACCOUNT_ID"
        continue
    fi
    
    export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
    export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
    
    # Empty S3 buckets
    log_info "  Emptying S3 buckets..."
    BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${STACK_PREFIX}')].Name" \
        --output text 2>/dev/null || echo "")
    
    for BUCKET in $BUCKETS; do
        log_info "    Emptying: $BUCKET"
        aws s3 rm "s3://${BUCKET}" --recursive --quiet 2>/dev/null || true
        aws s3 rb "s3://${BUCKET}" --force 2>/dev/null || true
    done
    
    # Delete ECR images
    log_info "  Deleting ECR images..."
    REPOS=$(aws ecr describe-repositories \
        --query "repositories[?contains(repositoryName, '${STACK_PREFIX}')].repositoryName" \
        --output text 2>/dev/null || echo "")
    
    for REPO in $REPOS; do
        log_info "    Cleaning: $REPO"
        IMAGE_IDS=$(aws ecr list-images \
            --repository-name "$REPO" \
            --query 'imageIds[*]' \
            --output json 2>/dev/null)
        
        if [ "$IMAGE_IDS" != "[]" ] && [ -n "$IMAGE_IDS" ]; then
            aws ecr batch-delete-image \
                --repository-name "$REPO" \
                --image-ids "$IMAGE_IDS" 2>/dev/null || true
        fi
    done
    
    # Delete CloudWatch log groups
    log_info "  Deleting CloudWatch log groups..."
    LOG_PREFIXES=(
        "/aws/lambda/${STACK_PREFIX}"
        "/aws/apprunner/${STACK_PREFIX}"
        "/aws/apigateway/${STACK_PREFIX}"
        "/aws/bedrock-agentcore/runtimes/${STACK_PREFIX}"
        "/aws/bedrock/modelinvocations"
        "/aws/bedrock/agentcore"
    )
    
    for PREFIX in "${LOG_PREFIXES[@]}"; do
        LOG_GROUPS=$(aws logs describe-log-groups \
            --log-group-name-prefix "$PREFIX" \
            --query 'logGroups[].logGroupName' \
            --output text 2>/dev/null || echo "")
        
        for LOG_GROUP in $LOG_GROUPS; do
            log_info "    Deleting: $LOG_GROUP"
            aws logs delete-log-group \
                --log-group-name "$LOG_GROUP" 2>/dev/null || true
        done
    done
    
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    log_success "  Account $ACCOUNT_ID cleaned"
done

# Final verification and forceful cleanup
log_info "=========================================="
log_info "Final Verification & Forceful Cleanup"
log_info "=========================================="

REMAINING_STACKSETS=$(aws cloudformation list-stack-sets \
    --region "$AWS_REGION" \
    --status ACTIVE \
    --query "Summaries[?contains(StackSetName, '${STACK_PREFIX}')].StackSetName" \
    --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_STACKSETS" ]; then
    log_success "✓ All StackSets deleted"
else
    log_warning "✗ Remaining StackSets found: $REMAINING_STACKSETS"
    log_info "=========================================="
    log_info "NUCLEAR OPTION - AGGRESSIVE CLEANUP"
    log_info "=========================================="
    log_warning "Initiating aggressive cleanup for stuck StackSets..."
    
    for STACKSET in $REMAINING_STACKSETS; do
        log_info "=========================================="
        log_info "Nuclear Cleanup: $STACKSET"
        log_info "=========================================="
        
        # For each account, do aggressive cleanup
        for ACCOUNT_ID in ${ACCOUNT_ARRAY[@]}; do
            log_info "Account $ACCOUNT_ID - Aggressive cleanup..."
            
            CREDS=$(aws sts assume-role \
                --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}" \
                --role-session-name "nuclear-${ACCOUNT_ID}" \
                --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
                --output text 2>/dev/null || echo "")
            
            if [ -z "$CREDS" ]; then
                log_warning "  Cannot assume role, skipping"
                continue
            fi
            
            export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
            export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
            export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
            
            # 1. Aggressively empty ALL S3 buckets
            log_info "  1. Emptying S3 buckets..."
            BUCKETS=$(aws s3api list-buckets \
                --query "Buckets[?contains(Name, '${STACK_PREFIX}')].Name" \
                --output text 2>/dev/null || echo "")
            
            for BUCKET in $BUCKETS; do
                log_info "     Bucket: $BUCKET"
                # Remove bucket policy
                aws s3api delete-bucket-policy --bucket "$BUCKET" 2>/dev/null || true
                # Disable versioning
                aws s3api put-bucket-versioning \
                    --bucket "$BUCKET" \
                    --versioning-configuration Status=Suspended 2>/dev/null || true
                # Delete all objects
                aws s3 rm "s3://${BUCKET}" --recursive --quiet 2>/dev/null || true
                # Delete all versions
                aws s3api list-object-versions \
                    --bucket "$BUCKET" \
                    --output json 2>/dev/null | \
                jq -r '.Versions[]?, .DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' 2>/dev/null | \
                while IFS=$'\t' read -r key version; do
                    [ -n "$key" ] && [ -n "$version" ] && \
                    aws s3api delete-object \
                        --bucket "$BUCKET" \
                        --key "$key" \
                        --version-id "$version" 2>/dev/null || true
                done
            done
            
            # 2. Delete Lambda functions (especially custom resources)
            log_info "  2. Deleting Lambda functions..."
            LAMBDAS=$(aws lambda list-functions \
                --region "$AWS_REGION" \
                --query "Functions[?contains(FunctionName, '${STACK_PREFIX}')].FunctionName" \
                --output text 2>/dev/null || echo "")
            
            for LAMBDA in $LAMBDAS; do
                log_info "     Lambda: $LAMBDA"
                aws lambda delete-function \
                    --function-name "$LAMBDA" \
                    --region "$AWS_REGION" 2>/dev/null || true
            done
            
            # 3. Delete ECR repositories
            log_info "  3. Deleting ECR repositories..."
            REPOS=$(aws ecr describe-repositories \
                --query "repositories[?contains(repositoryName, '${STACK_PREFIX}')].repositoryName" \
                --output text 2>/dev/null || echo "")
            
            for REPO in $REPOS; do
                log_info "     ECR: $REPO"
                aws ecr delete-repository \
                    --repository-name "$REPO" \
                    --force \
                    --region "$AWS_REGION" 2>/dev/null || true
            done
            
            # 4. Find ALL stacks for this StackSet
            log_info "  4. Finding stacks..."
            ALL_STACKS=$(aws cloudformation list-stacks \
                --region "$AWS_REGION" \
                --query "StackSummaries[?contains(StackName, 'StackSet-${STACKSET}')].{Name:StackName,Status:StackStatus}" \
                --output json 2>/dev/null || echo "[]")
            
            STACK_NAMES=$(echo "$ALL_STACKS" | jq -r '.[].Name')
            
            # 5. Handle failed stacks and delete
            for STACK in $STACK_NAMES; do
                STACK_STATUS=$(echo "$ALL_STACKS" | jq -r ".[] | select(.Name==\"$STACK\") | .Status")
                log_info "     Stack: $STACK (Status: $STACK_STATUS)"
                
                # If failed, try to continue rollback
                if [[ "$STACK_STATUS" == *"FAILED"* ]] || [[ "$STACK_STATUS" == "UPDATE_ROLLBACK_FAILED" ]]; then
                    log_info "     Attempting rollback continuation..."
                    aws cloudformation continue-update-rollback \
                        --stack-name "$STACK" \
                        --region "$AWS_REGION" 2>/dev/null || true
                    sleep 10
                fi
                
                # Delete the stack
                log_info "     Deleting stack..."
                aws cloudformation delete-stack \
                    --stack-name "$STACK" \
                    --region "$AWS_REGION" 2>/dev/null || true
            done
            
            # 6. Wait for stacks to delete (up to 10 minutes per stack)
            log_info "  5. Waiting for stack deletions..."
            for STACK in $STACK_NAMES; do
                for i in {1..120}; do
                    STACK_STATUS=$(aws cloudformation describe-stacks \
                        --stack-name "$STACK" \
                        --region "$AWS_REGION" \
                        --query 'Stacks[0].StackStatus' \
                        --output text 2>/dev/null || echo "DELETE_COMPLETE")
                    
                    if [ "$STACK_STATUS" == "DELETE_COMPLETE" ] || [ -z "$STACK_STATUS" ]; then
                        log_success "     Stack deleted: $STACK"
                        break
                    elif [[ "$STACK_STATUS" == *"FAILED"* ]]; then
                        log_error "     Stack deletion failed: $STACK_STATUS"
                        break
                    fi
                    
                    if [ $((i % 20)) -eq 0 ]; then
                        log_info "     Waiting... ($i/120) Status: $STACK_STATUS"
                    fi
                    
                    sleep 5
                done
            done
            
            unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
            log_success "  Account $ACCOUNT_ID cleanup complete"
        done
        
        # Now try to delete stack instances from StackSet
        log_info "Attempting to delete stack instances..."
        INSTANCES=$(aws cloudformation list-stack-instances \
            --stack-set-name "$STACKSET" \
            --region "$AWS_REGION" \
            --query 'Summaries[?Status!=`DELETED`]' \
            --output json 2>/dev/null || echo "[]")
        
        if [ "$INSTANCES" != "[]" ]; then
            REGIONS=$(echo "$INSTANCES" | jq -r '.[].Region' | sort -u | tr '\n' ' ')
            
            set +e
            OPERATION_ID=$(aws cloudformation delete-stack-instances \
                --stack-set-name "$STACKSET" \
                --deployment-targets OrganizationalUnitIds="$OU_ID" \
                --regions $REGIONS \
                --no-retain-stacks \
                --region "$AWS_REGION" \
                --query 'OperationId' \
                --output text 2>&1)
            set -e
            
            if [ -n "$OPERATION_ID" ] && [ "$OPERATION_ID" != "None" ]; then
                log_info "Operation started: $OPERATION_ID"
                
                # Wait for operation (up to 10 minutes)
                for i in {1..60}; do
                    OP_STATUS=$(aws cloudformation describe-stack-set-operation \
                        --stack-set-name "$STACKSET" \
                        --operation-id "$OPERATION_ID" \
                        --region "$AWS_REGION" \
                        --query 'StackSetOperation.Status' \
                        --output text 2>/dev/null || echo "UNKNOWN")
                    
                    if [ "$OP_STATUS" == "SUCCEEDED" ]; then
                        log_success "Operation completed successfully"
                        break
                    elif [ "$OP_STATUS" == "FAILED" ] || [ "$OP_STATUS" == "STOPPED" ]; then
                        log_warning "Operation status: $OP_STATUS"
                        break
                    fi
                    
                    if [ $((i % 10)) -eq 0 ]; then
                        log_info "Waiting... ($i/60) Status: $OP_STATUS"
                    fi
                    
                    sleep 10
                done
            fi
        fi
        
        # Final attempt to delete StackSet
        log_info "Attempting to delete StackSet..."
        FINAL_INSTANCES=$(aws cloudformation list-stack-instances \
            --stack-set-name "$STACKSET" \
            --region "$AWS_REGION" \
            --query 'Summaries[?Status!=`DELETED`]' \
            --output json 2>/dev/null || echo "[]")
        
        if [ "$FINAL_INSTANCES" == "[]" ]; then
            set +e
            aws cloudformation delete-stack-set \
                --stack-set-name "$STACKSET" \
                --region "$AWS_REGION" 2>&1
            
            if [ $? -eq 0 ]; then
                log_success "✓✓✓ StackSet $STACKSET deleted successfully!"
            else
                log_warning "✗ Failed to delete StackSet $STACKSET"
            fi
            set -e
        else
            log_error "✗ Cannot delete StackSet - instances still exist:"
            echo "$FINAL_INSTANCES" | jq -r '.[] | "    \(.Account) - \(.Region) - \(.Status)"'
            log_warning "Manual cleanup required in AWS Console"
        fi
    done
fi

log_success "=========================================="
log_success "CLEANUP COMPLETE!"
log_success "=========================================="

# Final status
FINAL_STACKSETS=$(aws cloudformation list-stack-sets \
    --region "$AWS_REGION" \
    --status ACTIVE \
    --query "Summaries[?contains(StackSetName, '${STACK_PREFIX}')].StackSetName" \
    --output text 2>/dev/null || echo "")

if [ -z "$FINAL_STACKSETS" ]; then
    log_success "✓ All StackSets successfully deleted"
else
    log_warning "⚠ Some StackSets remain: $FINAL_STACKSETS"
    log_info "These may require manual cleanup in the AWS Console"
fi
