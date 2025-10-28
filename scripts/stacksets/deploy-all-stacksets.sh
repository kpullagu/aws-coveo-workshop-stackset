#!/bin/bash
#
# Master deployment script for multi-account StackSets deployment
# Single command to deploy everything from master account to all child accounts
#

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env file if it exists
if [ -f ".env" ]; then
    echo "Loading environment variables from .env..."
    set -a
    source .env
    set +a
elif [ -f "../../.env" ]; then
    echo "Loading environment variables from ../../.env..."
    set -a
    source ../../.env
    set +a
fi

# Source configuration
source "$SCRIPT_DIR/config.sh"

# Validate environment variables
validate_env || exit 1

# Function to verify ECR images exist
verify_ecr_images() {
    log_info "Verifying ECR images exist..."
    
    local REQUIRED_IMAGES=(
        "${STACK_PREFIX}-coveo-mcp-server-master"
        "${STACK_PREFIX}-ui-master"
        "${STACK_PREFIX}-coveo-agent-master"
    )
    
    for IMAGE in "${REQUIRED_IMAGES[@]}"; do
        if aws ecr describe-repositories --repository-names "$IMAGE" --region "$AWS_REGION" >/dev/null 2>&1; then
            # Check if image has tags
            local TAG_COUNT=$(aws ecr list-images \
                --repository-name "$IMAGE" \
                --region "$AWS_REGION" \
                --query 'length(imageIds)' \
                --output text 2>/dev/null || echo "0")
            
            if [ "$TAG_COUNT" -gt 0 ]; then
                log_success "✓ ECR image exists: $IMAGE"
            else
                log_error "✗ ECR repository exists but no images: $IMAGE"
                return 1
            fi
        else
            log_error "✗ ECR repository missing: $IMAGE"
            return 1
        fi
    done
    
    log_success "All ECR images verified!"
}

# Function to verify Lambda Layer exists
verify_lambda_layer() {
    log_info "Verifying Lambda Layer exists..."
    
    local LAYER_ARN=$(aws ssm get-parameter \
        --name "/${STACK_PREFIX}/lambda-layer-arn" \
        --query "Parameter.Value" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -z "$LAYER_ARN" ]; then
        log_error "✗ Lambda Layer ARN not found in SSM"
        return 1
    fi
    
    # Verify layer actually exists
    local LAYER_NAME=$(echo "$LAYER_ARN" | cut -d':' -f7)
    local LAYER_VERSION=$(echo "$LAYER_ARN" | cut -d':' -f8)
    
    if aws lambda get-layer-version \
        --layer-name "$LAYER_NAME" \
        --version-number "$LAYER_VERSION" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_success "✓ Lambda Layer verified: $LAYER_ARN"
    else
        log_error "✗ Lambda Layer not accessible: $LAYER_ARN"
        return 1
    fi
}

# Function to verify Lambda packages exist in master bucket
verify_lambda_packages() {
    log_info "Verifying Lambda packages exist in master bucket..."
    
    local MASTER_CFN_BUCKET="${STACK_PREFIX}-${MASTER_ACCOUNT_ID}-cfn-templates"
    
    if ! aws s3 ls "s3://${MASTER_CFN_BUCKET}/lambdas/" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_error "✗ Lambda packages folder not found in master bucket"
        log_info "Run: bash scripts/stacksets/05-package-lambdas.sh"
        return 1
    fi
    
    local PACKAGE_COUNT=$(aws s3 ls "s3://${MASTER_CFN_BUCKET}/lambdas/" --region "$AWS_REGION" | wc -l)
    log_success "✓ Found $PACKAGE_COUNT Lambda packages in master bucket"
    log_info "S3 replication will automatically copy these to all child accounts"
}

# Function to wait for Layer 1 resources to be available
wait_for_layer1_resources() {
    log_info "Waiting for Layer 1 deployment to stabilize..."
    
    # Initial wait for instances to synchronize
    log_info "Waiting 30 seconds for instances to synchronize..."
    sleep 30
    
    # First, fix any OUTDATED instances (with 5 minute timeout per account)
    log_info "Fixing any OUTDATED instances..."
    fix_outdated_instances "workshop-layer1-prerequisites" 300
    
    # Check that all StackSet instances are CURRENT
    local RETRY_COUNT=0
    local MAX_RETRIES=20  # 5 minutes total (20 * 15 seconds)
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        local NON_CURRENT=$(aws cloudformation list-stack-instances \
            --stack-set-name "workshop-layer1-prerequisites" \
            --region "$AWS_REGION" \
            --query 'Summaries[?Status!=`CURRENT`].Account' \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$NON_CURRENT" ]; then
            log_success "✓ All Layer 1 instances are CURRENT"
            break
        fi
        
        log_info "  Waiting for Layer 1 to stabilize... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
        log_info "  Non-CURRENT accounts: $NON_CURRENT"
        
        # Show detailed status for non-CURRENT accounts
        for ACCOUNT_ID in $NON_CURRENT; do
            local ACCOUNT_STATUS=$(aws cloudformation list-stack-instances \
                --stack-set-name "workshop-layer1-prerequisites" \
                --stack-instance-account "$ACCOUNT_ID" \
                --stack-instance-region "$AWS_REGION" \
                --region "$AWS_REGION" \
                --query 'Summaries[0].[Status,StatusReason]' \
                --output text 2>/dev/null || echo "UNKNOWN Unknown")
            
            log_info "    Account $ACCOUNT_ID: $ACCOUNT_STATUS"
        done
        
        # Try to fix OUTDATED instances every 4 attempts (1 minute intervals)
        if [ $((RETRY_COUNT % 4)) -eq 0 ] && [ $RETRY_COUNT -gt 0 ]; then
            log_info "  Attempting to fix OUTDATED instances..."
            fix_outdated_instances "workshop-layer1-prerequisites" 180
        fi
        
        sleep 15
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        log_warning "✗ Layer 1 instances are not CURRENT after $MAX_RETRIES attempts"
        log_warning "Attempting one final fix with extended timeout..."
        fix_outdated_instances "workshop-layer1-prerequisites" 600
        
        # Final check
        local FINAL_NON_CURRENT=$(aws cloudformation list-stack-instances \
            --stack-set-name "workshop-layer1-prerequisites" \
            --region "$AWS_REGION" \
            --query 'Summaries[?Status!=`CURRENT`].Account' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$FINAL_NON_CURRENT" ]; then
            log_error "✗ Layer 1 instances still not CURRENT: $FINAL_NON_CURRENT"
            log_error "Deployment cannot continue without Layer 1 resources"
            log_info ""
            log_info "Troubleshooting steps:"
            log_info "  1. Check CloudFormation console for detailed errors"
            log_info "  2. Verify AWS Organizations permissions"
            log_info "  3. Check for resource limits or quotas"
            log_info "  4. Review CloudWatch Logs for stack events"
            log_info ""
            log_info "To manually fix and continue:"
            log_info "  bash scripts/stacksets/fix-layer1-and-continue.sh"
            return 1
        fi
    fi
    
    log_success "Layer 1 resources are ready!"
}



# Function to wait for StackSet to be fully deployed
wait_for_stackset_complete() {
    local STACKSET_NAME="$1"
    local MAX_WAIT="${2:-30}"  # Default 30 minutes
    
    log_info "Waiting for $STACKSET_NAME to be fully deployed..."
    
    # Initial wait for instances to be created and synchronized
    log_info "Waiting for stack instances to be created and synchronized..."
    sleep 30
    
    local ELAPSED=0
    local INITIAL_CHECK=true
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        # Get all instance statuses
        local ALL_STATUSES=$(aws cloudformation list-stack-instances \
            --stack-set-name "$STACKSET_NAME" \
            --region "$AWS_REGION" \
            --query 'Summaries[].[Account,Status,StackSetId]' \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$ALL_STATUSES" ]; then
            if [ "$INITIAL_CHECK" = true ]; then
                log_info "Instances not yet created, waiting..."
                sleep 15
                INITIAL_CHECK=false
                continue
            else
                log_warning "No instances found for $STACKSET_NAME after waiting"
                return 1
            fi
        fi
        
        INITIAL_CHECK=false
        
        # Check for any non-CURRENT statuses
        local NON_CURRENT=$(echo "$ALL_STATUSES" | grep -v "CURRENT" || echo "")
        
        if [ -z "$NON_CURRENT" ]; then
            log_success "All instances are CURRENT"
            
            # Additional check: Verify actual CloudFormation stacks are CREATE_COMPLETE or UPDATE_COMPLETE
            log_info "Verifying CloudFormation stack statuses..."
            local ALL_COMPLETE=true
            
            # Get list of accounts
            local ACCOUNTS=$(echo "$ALL_STATUSES" | awk '{print $1}' | sort -u)
            
            for ACCOUNT_ID in $ACCOUNTS; do
                # Check if stack exists and is in a stable state
                local STACK_STATUS=$(aws cloudformation list-stack-instances \
                    --stack-set-name "$STACKSET_NAME" \
                    --stack-instance-account "$ACCOUNT_ID" \
                    --stack-instance-region "$AWS_REGION" \
                    --region "$AWS_REGION" \
                    --query 'Summaries[0].StackInstanceStatus.DetailedStatus' \
                    --output text 2>/dev/null || echo "UNKNOWN")
                
                if [[ "$STACK_STATUS" != "SUCCEEDED" ]]; then
                    log_info "  Account $ACCOUNT_ID: $STACK_STATUS (waiting...)"
                    ALL_COMPLETE=false
                fi
            done
            
            if [ "$ALL_COMPLETE" = true ]; then
                log_success "All stacks are fully deployed and stable"
                
                # Final check: Fix any OUTDATED instances before returning
                log_info "Final check: Fixing any OUTDATED instances..."
                fix_outdated_instances "$STACKSET_NAME"
                
                return 0
            fi
        else
            log_info "Waiting for instances to complete... ($ELAPSED/$MAX_WAIT minutes)"
            echo "$NON_CURRENT" | while read line; do
                log_info "  $line"
            done
            
            # Check if any instances are OUTDATED and fix them
            local OUTDATED_COUNT=$(echo "$NON_CURRENT" | grep -c "OUTDATED" || echo "0")
            if [ "$OUTDATED_COUNT" -gt 0 ]; then
                log_info "Found $OUTDATED_COUNT OUTDATED instances, fixing..."
                # Use shorter timeout for intermediate fixes
                fix_outdated_instances "$STACKSET_NAME" 180
            fi
        fi
        
        sleep 60
        ELAPSED=$((ELAPSED + 1))
    done
    
    log_warning "Timeout waiting for $STACKSET_NAME to complete after $MAX_WAIT minutes"
    log_warning "Some instances may still be deploying"
    return 1
}

# Function to fix OUTDATED instances
fix_outdated_instances() {
    local STACKSET_NAME="$1"
    local MAX_WAIT_PER_ACCOUNT="${2:-300}"  # 5 minutes per account default
    
    log_info "Checking for OUTDATED instances in $STACKSET_NAME..."
    
    # Get OUTDATED accounts for this StackSet
    local OUTDATED_ACCOUNTS=$(aws cloudformation list-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --region "$AWS_REGION" \
        --query 'Summaries[?Status==`OUTDATED`].Account' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$OUTDATED_ACCOUNTS" ]; then
        log_success "No OUTDATED instances found"
        return 0
    fi
    
    log_warning "Found OUTDATED accounts: $OUTDATED_ACCOUNTS"
    log_info "Updating OUTDATED instances..."
    
    # Update instances for OUTDATED accounts
    for ACCOUNT_ID in $OUTDATED_ACCOUNTS; do
        log_info "Updating account: $ACCOUNT_ID"
        
        local OPERATION_ID=$(aws cloudformation update-stack-instances \
            --stack-set-name "$STACKSET_NAME" \
            --accounts $ACCOUNT_ID \
            --regions $AWS_REGION \
            --region "$AWS_REGION" \
            --query 'OperationId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$OPERATION_ID" ]; then
            log_info "Update operation started: $OPERATION_ID"
            
            # Wait for operation to complete with timeout
            log_info "Waiting for operation to complete (max ${MAX_WAIT_PER_ACCOUNT}s)..."
            
            local WAIT_START=$(date +%s)
            local OPERATION_STATUS="RUNNING"
            
            while [ "$OPERATION_STATUS" = "RUNNING" ] || [ "$OPERATION_STATUS" = "QUEUED" ]; do
                local CURRENT_TIME=$(date +%s)
                local ELAPSED=$((CURRENT_TIME - WAIT_START))
                
                if [ $ELAPSED -gt $MAX_WAIT_PER_ACCOUNT ]; then
                    log_warning "⚠️  Operation timeout after ${MAX_WAIT_PER_ACCOUNT}s for account $ACCOUNT_ID"
                    log_warning "Operation may still be running in background"
                    break
                fi
                
                # Check operation status
                OPERATION_STATUS=$(aws cloudformation describe-stack-set-operation \
                    --stack-set-name "$STACKSET_NAME" \
                    --operation-id "$OPERATION_ID" \
                    --region "$AWS_REGION" \
                    --query 'StackSetOperation.Status' \
                    --output text 2>/dev/null || echo "UNKNOWN")
                
                if [ "$OPERATION_STATUS" = "SUCCEEDED" ]; then
                    log_success "✓ Operation completed successfully"
                    break
                elif [ "$OPERATION_STATUS" = "FAILED" ] || [ "$OPERATION_STATUS" = "STOPPED" ]; then
                    log_error "✗ Operation failed with status: $OPERATION_STATUS"
                    
                    # Get failure reason
                    local FAILURE_REASON=$(aws cloudformation describe-stack-set-operation \
                        --stack-set-name "$STACKSET_NAME" \
                        --operation-id "$OPERATION_ID" \
                        --region "$AWS_REGION" \
                        --query 'StackSetOperation.StatusReason' \
                        --output text 2>/dev/null || echo "Unknown")
                    
                    log_error "Reason: $FAILURE_REASON"
                    break
                fi
                
                log_info "  Status: $OPERATION_STATUS (${ELAPSED}s elapsed)"
                sleep 10
            done
            
            # Check final instance status
            local FINAL_STATUS=$(aws cloudformation list-stack-instances \
                --stack-set-name "$STACKSET_NAME" \
                --stack-instance-account "$ACCOUNT_ID" \
                --stack-instance-region "$AWS_REGION" \
                --region "$AWS_REGION" \
                --query 'Summaries[0].Status' \
                --output text 2>/dev/null || echo "UNKNOWN")
            
            if [ "$FINAL_STATUS" = "CURRENT" ]; then
                log_success "✓ Account $ACCOUNT_ID is now CURRENT"
            else
                log_warning "✗ Account $ACCOUNT_ID status: $FINAL_STATUS"
                
                # Get detailed status
                local DETAILED_STATUS=$(aws cloudformation list-stack-instances \
                    --stack-set-name "$STACKSET_NAME" \
                    --stack-instance-account "$ACCOUNT_ID" \
                    --stack-instance-region "$AWS_REGION" \
                    --region "$AWS_REGION" \
                    --query 'Summaries[0].StatusReason' \
                    --output text 2>/dev/null || echo "Unknown")
                
                if [ "$DETAILED_STATUS" != "Unknown" ] && [ "$DETAILED_STATUS" != "None" ]; then
                    log_info "  Reason: $DETAILED_STATUS"
                fi
            fi
        else
            log_warning "✗ No operation ID returned for account $ACCOUNT_ID"
        fi
        
        # Small delay between accounts to avoid throttling
        sleep 2
    done
}

# Show configuration
show_config

echo ""
log_info "=========================================="
log_info "Multi-Account StackSets Deployment"
log_info "=========================================="
log_info "Master Account: $MASTER_ACCOUNT_ID"
log_info "Region: $AWS_REGION"
log_info "Target OU: $OU_ID"
log_info "Stack Prefix: $STACK_PREFIX"
echo ""

# Get child accounts for validation
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

ACCOUNT_COUNT=$(echo $ACCOUNT_IDS | wc -w)
log_info "Target accounts ($ACCOUNT_COUNT): $ACCOUNT_IDS"
echo ""

# Pre-deployment validation
log_info "=========================================="
log_info "Pre-Deployment Validation"
log_info "=========================================="

# Check if this is a fresh deployment or re-deployment
EXISTING_STACKSETS=$(aws cloudformation list-stack-sets \
    --region "$AWS_REGION" \
    --query "Summaries[?starts_with(StackSetName, 'workshop-')].StackSetName" \
    --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_STACKSETS" ]; then
    log_warning "Existing StackSets found: $EXISTING_STACKSETS"
    log_info "This appears to be a re-deployment or repair operation"
    
    # Check for any failed instances
    for STACKSET in $EXISTING_STACKSETS; do
        FAILED_INSTANCES=$(aws cloudformation list-stack-instances \
            --stack-set-name "$STACKSET" \
            --region "$AWS_REGION" \
            --query 'Summaries[?Status!=`CURRENT`].[Account,Status]' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$FAILED_INSTANCES" ]; then
            log_warning "StackSet $STACKSET has non-CURRENT instances:"
            echo "$FAILED_INSTANCES"
        fi
    done
    echo ""
else
    log_info "No existing StackSets found - this is a fresh deployment"
fi

# Confirm deployment
read -p "Deploy to all $ACCOUNT_COUNT accounts in OU $OU_ID? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  log_warning "Deployment cancelled"
  exit 0
fi

# Step 1: Setup master account
log_info "Step 1: Setting up master account..."
bash scripts/stacksets/01-setup-master-ecr.sh
log_success "Master account setup complete"

# Step 2: Build and push MCP image
log_info "Step 2: Building and pushing MCP Server image..."
bash scripts/stacksets/02-build-push-mcp-image.sh
log_success "MCP Server image pushed"

# Step 3: Build and push UI image
log_info "Step 3: Building and pushing UI image..."
bash scripts/stacksets/03-build-push-ui-image.sh
log_success "UI image pushed"

# Step 3.5: Build and push Coveo Agent image
log_info "Step 3.5: Building and pushing Coveo Agent image..."
bash scripts/stacksets/02b-build-push-agent-image.sh
log_success "Coveo Agent image pushed"

# Verify all ECR images are available
verify_ecr_images

# Step 3.9: Update ECR repository policies for cross-account access
log_info "Step 3.9: Updating ECR repository policies for cross-account access..."
if [ -f scripts/stacksets/update-ecr-repo-policy.sh ]; then
    bash scripts/stacksets/update-ecr-repo-policy.sh
    log_success "ECR repository policies updated"
else
    log_warning "update-ecr-repo-policy.sh not found, skipping"
fi

# Step 4: Create shared Lambda layer
log_info "Step 4: Creating shared Lambda layer..."
bash scripts/stacksets/04-create-shared-lambda-layer.sh

# Verify Lambda layer is available
verify_lambda_layer

# Step 4.5: Ensure Lambda layer permissions are correct
log_info "Step 4.5: Verifying Lambda layer permissions..."
log_info "This may take a moment..."

# Run with timeout to prevent hanging
timeout 120 bash scripts/stacksets/fix-lambda-layer-permissions.sh || {
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        log_warning "Lambda layer permission script timed out, but continuing..."
        log_info "You can verify permissions later with: bash scripts/stacksets/fix-lambda-layer-permissions.sh"
    else
        log_warning "Lambda layer permission script had issues, but continuing..."
    fi
}

log_success "Lambda layer created and permissions verified"

# Step 5: Package Lambda functions
log_info "Step 5: Packaging Lambda functions..."
bash scripts/stacksets/05-package-lambdas.sh

# Verify Lambda packages are available
verify_lambda_packages
log_success "Lambda functions packaged and verified"

# Step 6: Deploy Layer 1 - Prerequisites
log_info "Step 6: Deploying Layer 1 - Prerequisites..."
bash scripts/stacksets/10-deploy-layer1-prerequisites.sh

# Wait for Layer 1 resources to be available (with OUTDATED fixing)
wait_for_layer1_resources || log_warning "Layer 1 may not be fully ready, but continuing..."
log_success "Layer 1 deployed"

# Step 6.5: Setup S3 cross-account replication (ENHANCED)
log_info "Step 6.5: Setting up S3 cross-account replication..."
if [ -f scripts/stacksets/06-setup-s3-replication-v2.sh ]; then
    bash scripts/stacksets/06-setup-s3-replication-v2.sh
else
    bash scripts/stacksets/06-setup-s3-replication.sh
fi
log_success "S3 replication configured"

# Step 6.6: Force re-upload Lambda packages to trigger replication
log_info "Step 6.6: Re-uploading Lambda packages to trigger replication..."
if [ -f scripts/stacksets/force-lambda-resync.sh ]; then
    bash scripts/stacksets/force-lambda-resync.sh
    log_success "Lambda packages re-uploaded"
else
    log_warning "force-lambda-resync.sh not found, skipping re-upload"
fi

# Step 6.7: Active replication test
log_info "Step 6.7: Testing replication with probe file..."
if [ -f scripts/stacksets/test-active-replication.sh ]; then
    if bash scripts/stacksets/test-active-replication.sh; then
        log_success "Active replication test PASSED"
    else
        log_warning "Active replication test FAILED - will wait longer"
    fi
else
    log_warning "test-active-replication.sh not found, skipping test"
fi

# Step 6.8: Wait for full replication to complete
log_info "Step 6.8: Waiting for full Lambda package replication..."
log_info "S3 replication typically completes within 5-15 minutes"
log_info "Waiting 10 minutes to ensure all packages are replicated..."
sleep 600
log_success "Replication wait period complete"

# Step 6.9: Seed SSM Parameters (BEFORE Layer 2)
log_info "Step 6.9: Seeding SSM Parameters in all accounts..."
log_info "This MUST happen before Layer 2 deployment!"
bash scripts/stacksets/07-seed-ssm-parameters.sh
log_success "SSM parameters seeded"

# Step 7: Deploy Layer 2 - Core Infrastructure
log_info "Step 7: Deploying Layer 2 - Core Infrastructure..."
bash scripts/stacksets/11-deploy-layer2-core.sh

# Wait for Layer 2 to be fully deployed before proceeding
log_info "Waiting for Layer 2 to complete (exports must be available for Layer 3)..."
wait_for_stackset_complete "workshop-layer2-core" 30
fix_outdated_instances "workshop-layer2-core"

# Verify critical exports are available
log_info "Verifying Layer 2 exports are available..."
sleep 30  # Give AWS time to register exports
log_success "Layer 2 deployed and ready"

# Step 8: Deploy Layer 3 - AI Services
log_info "Step 8: Deploying Layer 3 - AI Services..."
log_info "This layer creates AgentCore Runtimes and SSM parameters"
bash scripts/stacksets/12-deploy-layer3-ai-services.sh

# Wait for Layer 3 to be fully deployed before proceeding
log_info "Waiting for Layer 3 to complete (this may take 10-15 minutes)..."
wait_for_stackset_complete "workshop-layer3-ai-services" 30
fix_outdated_instances "workshop-layer3-ai-services"

# Give extra time for AgentCore resources to be fully ready
log_info "Waiting for AgentCore resources to be fully initialized..."
sleep 60
log_success "Layer 3 deployed and ready"

# Step 8.5: Seed Agent SSM Parameters (immediately after Layer 3)
log_info "Step 8.5: Seeding Agent SSM parameters..."
log_info "This creates SSM parameters needed by Agent Runtime from Layer 3 outputs"
bash scripts/stacksets/12b-seed-agent-ssm-parameters.sh
log_success "Agent SSM parameters seeded"

# Step 8.6: Enable Bedrock Model Invocation Logging
log_info "Step 8.6: Enabling Bedrock model invocation logging..."
bash scripts/stacksets/enable-bedrock-model-invocation-logging.sh
log_success "Bedrock model invocation logging enabled"

# Step 9: Deploy Layer 4 - UI
log_info "Step 9: Deploying Layer 4 - UI..."
log_info "This layer creates App Runner services"
bash scripts/stacksets/13-deploy-layer4-ui.sh

# Wait for Layer 4 to be fully deployed
log_info "Waiting for Layer 4 to complete (App Runner deployment may take 5-10 minutes)..."
wait_for_stackset_complete "workshop-layer4-ui" 25
fix_outdated_instances "workshop-layer4-ui"

# Give App Runner time to fully start
log_info "Waiting for App Runner services to be fully running..."
sleep 60
log_success "Layer 4 deployed and ready"

# Step 9.5: Enable X-Ray CloudWatch Logs ingestion for observability
log_info "Step 9.5: Enabling X-Ray CloudWatch Logs ingestion..."
log_info "This enables trace viewing in Bedrock AgentCore Observability dashboard"
bash scripts/stacksets/enable-xray-cloudwatch-ingestion.sh
log_success "X-Ray CloudWatch Logs ingestion enabled"

# Step 10: Post-deployment configuration and collect deployment information
log_info "Step 10: Post-deployment configuration and collecting deployment information..."
log_info "This includes: SSM parameters, Cognito test users, callback URLs, App Runner env vars, and deployment info"
bash scripts/stacksets/14-post-deployment-config.sh
log_success "Post-deployment configuration complete and deployment information collected"

# Final comprehensive status check
echo ""
log_info "=========================================="
log_info "Final Deployment Verification"
log_info "=========================================="

# Check all StackSets final status
STACKSETS=(
    "workshop-layer1-prerequisites"
    "workshop-layer2-core"
    "workshop-layer3-ai-services"
    "workshop-layer4-ui"
)

ALL_SUCCESS=true
for STACKSET in "${STACKSETS[@]}"; do
    echo ""
    log_info "StackSet: $STACKSET"
    
    # Get status of all instances
    INSTANCE_STATUS=$(aws cloudformation list-stack-instances \
        --stack-set-name "$STACKSET" \
        --region "$AWS_REGION" \
        --query 'Summaries[*].[Account,Status]' \
        --output table 2>/dev/null || echo "ERROR")
    
    if [ "$INSTANCE_STATUS" = "ERROR" ]; then
        log_error "✗ Could not get status for $STACKSET"
        ALL_SUCCESS=false
    else
        echo "$INSTANCE_STATUS"
        
        # Check for any non-CURRENT instances
        NON_CURRENT=$(aws cloudformation list-stack-instances \
            --stack-set-name "$STACKSET" \
            --region "$AWS_REGION" \
            --query 'Summaries[?Status!=`CURRENT`].Account' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$NON_CURRENT" ]; then
            log_warning "⚠ Non-CURRENT instances in accounts: $NON_CURRENT"
            ALL_SUCCESS=false
        fi
    fi
done

echo ""
if [ "$ALL_SUCCESS" = true ]; then
    log_success "=========================================="
    log_success "🎉 DEPLOYMENT FULLY SUCCESSFUL! 🎉"
    log_success "=========================================="
    echo ""
    log_info "All StackSets deployed successfully to all accounts!"
    echo ""
    log_info "Next steps:"
    echo "1. ✅ All resources are deployed and ready"
    echo "2. 🧪 Test functionality in sample accounts"
    echo "3. 📋 Collect App Runner URLs from accounts"
    echo "4. 👥 Distribute URLs to workshop participants"
    echo ""
    log_info "Useful commands:"
    echo "  # Get App Runner URLs from all accounts"
    echo "  bash scripts/show-deployment-info.sh"
    echo ""
    echo "  # Monitor ongoing status"
    echo "  bash scripts/stacksets/monitor-all-stacksets.sh"
    echo ""
    echo "  # Complete cleanup after workshop"
    echo "  bash scripts/stacksets/destroy-all-stacksets.sh"
else
    log_warning "=========================================="
    log_warning "⚠️  DEPLOYMENT COMPLETED WITH ISSUES ⚠️"
    log_warning "=========================================="
    echo ""
    log_info "Some StackSet instances are not in CURRENT state."
    echo ""
    log_info "Troubleshooting steps:"
    echo "1. 🔍 Check detailed status:"
    echo "   bash scripts/stacksets/check-all-stackset-status.sh"
    echo ""
    echo "2. 🔧 Fix OUTDATED instances:"
    echo "   bash scripts/stacksets/fix-all-outdated-instances.sh"
    echo ""
    echo "3. 🚀 Force redeploy if needed:"
    echo "   bash scripts/stacksets/force-redeploy-all-layers.sh"
fi

echo ""
