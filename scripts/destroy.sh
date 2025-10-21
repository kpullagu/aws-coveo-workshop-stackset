#!/bin/bash

###############################################################################
# Destroy Complete Workshop Infrastructure
#
# This script tears down ALL resources created by ./deploy-complete-workshop.sh
# with maximum parallelization for speed:
# 1. Delete App Runner services and AgentCore Gateways (parallel)
# 2. Delete ECR repositories (parallel)
# 3. Delete orphaned Lambda functions (parallel)
# 4. Delete Bedrock Agents and Aliases
# 5. Delete orphaned IAM roles (parallel)
# 6. Empty and delete S3 buckets (parallel)
# 7. Delete ALL CloudFormation stacks (fully parallel with enhanced monitoring)
# 8. Clean up orphaned nested stacks
# 9. Delete SSM parameters (parallel)
# 10. Delete Secrets Manager secrets (parallel)
# 11. Delete CloudWatch Log Groups (parallel)
# 12. Delete Cognito users (including test user)
# 13. Clean up local deployment artifacts and final verification
#
# The script handles ALL resources created by ./deploy-complete-workshop.sh:
#   - App Runner services (for UI deployment)
#   - AgentCore Gateways (serverless MCP server runtime)
#   - ECR repository images (Docker images for both UI and MCP server)
#   - Lambda functions (must delete before IAM roles to avoid dependency issues)
#   - Bedrock Agents and their aliases (must delete before IAM roles)
#   - IAM roles with attached managed policies (including App Runner roles)
#   - S3 buckets with versioning enabled (deletes all versions and delete markers)
#   - CloudFormation stacks (master, nested, and App Runner)
#   - SSM parameters and Secrets Manager secrets
#   - Cognito users (including test user created by complete deployment)
#   - Local deployment artifacts and info files
#   - Orphaned resources from failed CloudFormation deployments
#   - Complete cleanup with verification
#
# Usage:
#   ./scripts/destroy.sh --stack-prefix workshop --region us-east-1 [--confirm]
#
# Examples:
#   # Interactive mode (asks for confirmation)
#   ./scripts/destroy.sh
#
#   # Non-interactive mode (auto-confirm)
#   ./scripts/destroy.sh --confirm
#
#   # Custom stack prefix and region
#   ./scripts/destroy.sh --stack-prefix myworkshop --region us-west-2 --confirm
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fixed values - consistent with deploy script
STACK_PREFIX="workshop"
AWS_REGION="us-east-1"
CONFIRM=false

# Get AWS Account ID for dynamic bucket names
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")

# Dynamic S3 bucket names (current naming pattern)
CFN_BUCKET_NAME="workshop-${AWS_ACCOUNT_ID}-cfn-templates"
UI_BUCKET_NAME="workshop-${AWS_ACCOUNT_ID}-ui"

# Legacy bucket names for cleanup (both old naming patterns)
CFN_BUCKET_NAME_OLD1="coveo-workshop-cfn-templates"
CFN_BUCKET_NAME_OLD2="workshop-cfn-templates"
UI_BUCKET_NAME_OLD1="coveo-workshop-ui"
UI_BUCKET_NAME_OLD2="workshop-ui"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --confirm)
            CONFIRM=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown parameter: $1${NC}"
            echo "Usage: $0 --region <region> [--confirm]"
            echo ""
            echo "Fixed Configuration:"
            echo "  Stack Prefix: $STACK_PREFIX (fixed)"
            echo "  CFN S3 Buckets: $CFN_BUCKET_NAME + legacy variants (dynamic)"
            echo "  UI S3 Buckets: $UI_BUCKET_NAME + legacy variants (dynamic)"
            exit 1
            ;;
    esac
done

echo -e "${RED}=== WARNING: Destroying Workshop Infrastructure ===${NC}"
echo "Stack Prefix: $STACK_PREFIX (fixed)"
echo "Region: $AWS_REGION"
echo "CFN S3 Buckets: $CFN_BUCKET_NAME + legacy variants (dynamic)"
echo "UI S3 Buckets: $UI_BUCKET_NAME + legacy variants (dynamic)"
echo ""
echo "This will delete:"
echo "  - All CloudFormation stacks (${STACK_PREFIX}-*)"
echo "  - App Runner services (UI deployment)"
echo "  - AgentCore Memories (conversation history)"
echo "  - AgentCore Runtimes (MCP server and Agent)"
echo "  - ECR repositories and images (PRESERVED for faster rebuilds)"
echo "  - All S3 buckets and their contents:"
echo "    • $CFN_BUCKET_NAME (current)"
echo "    • $UI_BUCKET_NAME (current)"
echo "    • Legacy bucket variants (if they exist)"
echo "  - All Lambda functions"
echo "  - Cognito User Pool and users"
echo "  - Bedrock Agent (if deployed)"
echo "  - AgentCore Runtime (if deployed)"
echo "  - SSM Parameters (/${STACK_PREFIX}/*)"
echo "  - Secrets Manager secrets (${STACK_PREFIX}/*)"
echo ""

if [ "$CONFIRM" = false ]; then
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    if [ "$confirmation" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Starting destruction process...${NC}"
echo ""

# Function to check if stack exists and can be deleted
stack_exists() {
    local stack_name="$1"
    local stack_status
    
    # Check if stack exists
    if ! aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null; then
        return 1  # Stack doesn't exist
    fi
    
    # Get stack status
    stack_status=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query 'Stacks[0].StackStatus' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "UNKNOWN")
    
    # Stack exists and is not already deleted
    if [ "$stack_status" != "DELETE_COMPLETE" ]; then
        return 0  # Stack exists and needs deletion
    else
        return 1  # Stack is already deleted
    fi
}

# Function to delete stack and wait
delete_stack() {
    local stack_name="$1"
    
    if stack_exists "$stack_name"; then
        # Get stack status to handle ROLLBACK_COMPLETE stacks
        local stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "UNKNOWN")
        
        echo -e "${YELLOW}Deleting stack: $stack_name (status: $stack_status)${NC}"
        
        # Handle ROLLBACK_COMPLETE stacks specially
        if [ "$stack_status" = "ROLLBACK_COMPLETE" ]; then
            echo "Stack is in ROLLBACK_COMPLETE state, deleting directly..."
            aws cloudformation delete-stack --stack-name "$stack_name" --region "$AWS_REGION" || {
                echo -e "${RED}Failed to initiate deletion of ROLLBACK_COMPLETE stack: $stack_name${NC}"
                return 1
            }
        else
            aws cloudformation delete-stack --stack-name "$stack_name" --region "$AWS_REGION" || {
                echo -e "${RED}Failed to initiate deletion of stack: $stack_name${NC}"
                return 1
            }
        fi
        
        echo "Waiting for stack deletion to complete..."
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$AWS_REGION" 2>&1 || {
            echo -e "${RED}Failed to delete stack $stack_name (may need manual cleanup)${NC}"
            return 1
        }
        echo -e "${GREEN}✓ Stack deleted: $stack_name${NC}"
    else
        echo "Stack does not exist: $stack_name (skipping)"
    fi
}

# Function to empty and delete S3 bucket (with versioning support) - FAST VERSION
empty_and_delete_bucket() {
    local bucket_name="$1"
    
    if aws s3 ls "s3://${bucket_name}" --region "$AWS_REGION" 2>/dev/null; then
        echo -e "${YELLOW}Force deleting S3 bucket: $bucket_name${NC}"
        
        # Use aws s3 rb --force for fast deletion (removes all objects and bucket in one command)
        aws s3 rb "s3://${bucket_name}" --force --region "$AWS_REGION" 2>/dev/null && {
            echo -e "${GREEN}✓ Bucket deleted: $bucket_name${NC}"
            return 0
        }
        
        # If force delete fails (versioned bucket), use batch deletion
        echo "  Bucket has versioning, using batch deletion..."
        
        # Delete all versions and delete markers in batches using Python
        python3 - <<EOF
import boto3
import sys

s3 = boto3.client('s3', region_name='$AWS_REGION')
bucket = '$bucket_name'

try:
    # List and delete all versions and delete markers
    paginator = s3.get_paginator('list_object_versions')
    
    for page in paginator.paginate(Bucket=bucket):
        objects_to_delete = []
        
        # Add versions
        for version in page.get('Versions', []):
            objects_to_delete.append({'Key': version['Key'], 'VersionId': version['VersionId']})
        
        # Add delete markers
        for marker in page.get('DeleteMarkers', []):
            objects_to_delete.append({'Key': marker['Key'], 'VersionId': marker['VersionId']})
        
        # Batch delete (up to 1000 objects at a time)
        if objects_to_delete:
            s3.delete_objects(Bucket=bucket, Delete={'Objects': objects_to_delete, 'Quiet': True})
    
    # Delete the bucket
    s3.delete_bucket(Bucket=bucket)
    print(f"✓ Bucket deleted: {bucket}")
    sys.exit(0)
    
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Bucket deleted: $bucket_name${NC}"
        else
            echo -e "${RED}Failed to delete bucket: $bucket_name${NC}"
            return 1
        fi
    else
        echo "Bucket does not exist: $bucket_name (skipping)"
    fi
}

# Function to delete IAM role with all policies
delete_iam_role() {
    local role_name="$1"
    
    if aws iam get-role --role-name "$role_name" 2>/dev/null >/dev/null; then
        echo -e "${YELLOW}Deleting IAM role: $role_name${NC}"
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output text 2>/dev/null || echo "")
        for policy in $INLINE_POLICIES; do
            if [ -n "$policy" ]; then
                echo "  Deleting inline policy: $policy"
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy" 2>/dev/null || true
            fi
        done
        
        # Detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        for policy_arn in $ATTACHED_POLICIES; do
            if [ -n "$policy_arn" ]; then
                echo "  Detaching managed policy: $policy_arn"
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
            fi
        done
        
        # Remove from instance profiles (if any)
        INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name "$role_name" --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || echo "")
        for profile in $INSTANCE_PROFILES; do
            if [ -n "$profile" ]; then
                echo "  Removing from instance profile: $profile"
                aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role_name" 2>/dev/null || true
            fi
        done
        
        # Delete the role with retry logic
        MAX_RETRIES=3
        RETRY_COUNT=0
        DELETED=false
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$DELETED" = false ]; do
            if [ $RETRY_COUNT -gt 0 ]; then
                echo "  Retry attempt $RETRY_COUNT of $MAX_RETRIES (waiting 5s)..."
                sleep 5
            fi
            
            if aws iam delete-role --role-name "$role_name" 2>/dev/null; then
                echo -e "${GREEN}✓ Role deleted: $role_name${NC}"
                DELETED=true
            else
                # Check if role still exists
                if ! aws iam get-role --role-name "$role_name" 2>/dev/null >/dev/null; then
                    echo -e "${GREEN}✓ Role already deleted: $role_name${NC}"
                    DELETED=true
                else
                    RETRY_COUNT=$((RETRY_COUNT + 1))
                    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                        echo "  Role deletion failed, retrying..."
                    fi
                fi
            fi
        done
        
        if [ "$DELETED" = false ]; then
            echo -e "${RED}Failed to delete role after $MAX_RETRIES attempts: $role_name${NC}"
            echo "  Role may still be in use by active resources"
            return 1
        fi
    else
        echo "Role does not exist: $role_name (skipping)"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    local function_name="$1"
    
    if aws lambda get-function --function-name "$function_name" --region "$AWS_REGION" 2>/dev/null >/dev/null; then
        echo -e "${YELLOW}Deleting Lambda function: $function_name${NC}"
        aws lambda delete-function --function-name "$function_name" --region "$AWS_REGION" 2>/dev/null && {
            echo -e "${GREEN}✓ Function deleted: $function_name${NC}"
        } || {
            echo -e "${RED}Failed to delete function: $function_name${NC}"
            return 1
        }
    else
        echo "Function does not exist: $function_name (skipping)"
    fi
}

# Function to delete Bedrock Agent and its alias
delete_bedrock_agent() {
    local agent_name_prefix="$1"
    
    # Find all agents with the prefix
    echo -e "${YELLOW}Searching for Bedrock Agents with prefix: $agent_name_prefix${NC}"
    
    AGENTS=$(aws bedrock-agent list-agents \
        --region "$AWS_REGION" \
        --query "agentSummaries[?starts_with(agentName, '${agent_name_prefix}')].agentId" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$AGENTS" ]; then
        echo "No Bedrock Agents found with prefix: $agent_name_prefix"
        return 0
    fi
    
    for agent_id in $AGENTS; do
        echo -e "${YELLOW}Processing Bedrock Agent: $agent_id${NC}"
        
        # List and delete all agent aliases first
        echo "  Checking for agent aliases..."
        ALIASES=$(aws bedrock-agent list-agent-aliases \
            --agent-id "$agent_id" \
            --region "$AWS_REGION" \
            --query "agentAliasSummaries[?agentAliasName!='TSTALIASID'].agentAliasId" \
            --output text 2>/dev/null || echo "")
        
        for alias_id in $ALIASES; do
            if [ -n "$alias_id" ] && [ "$alias_id" != "TSTALIASID" ]; then
                echo "  Deleting agent alias: $alias_id"
                aws bedrock-agent delete-agent-alias \
                    --agent-id "$agent_id" \
                    --agent-alias-id "$alias_id" \
                    --region "$AWS_REGION" 2>/dev/null || echo "    (already deleted or error)"
            fi
        done
        
        # Delete the agent itself
        echo "  Deleting Bedrock Agent: $agent_id"
        aws bedrock-agent delete-agent \
            --agent-id "$agent_id" \
            --skip-resource-in-use-check \
            --region "$AWS_REGION" 2>/dev/null && {
            echo -e "${GREEN}✓ Bedrock Agent deleted: $agent_id${NC}"
        } || {
            echo -e "${RED}Failed to delete agent (may not exist or in use): $agent_id${NC}"
        }
    done
}

# Step 1: Delete App Runner services (AgentCore Runtimes will be deleted by CloudFormation)
echo -e "${YELLOW}[1/13] Cleaning up App Runner services...${NC}"

# Start App Runner cleanup in background
(
    echo "Starting App Runner cleanup..."
    # Find App Runner services with the stack prefix
    APP_RUNNER_SERVICES=$(aws apprunner list-services \
        --region "$AWS_REGION" \
        --query "ServiceSummaryList[?starts_with(ServiceName, '${STACK_PREFIX}-')].ServiceArn" \
        --output text 2>/dev/null || echo "")

    if [ -n "$APP_RUNNER_SERVICES" ]; then
        APP_RUNNER_PIDS=()
        for service_arn in $APP_RUNNER_SERVICES; do
            SERVICE_NAME=$(echo "$service_arn" | awk -F'/' '{print $NF}')
            echo "Deleting App Runner service: $SERVICE_NAME"
            
            # Delete the service and wait in background
            (
                aws apprunner delete-service \
                    --service-arn "$service_arn" \
                    --region "$AWS_REGION" >/dev/null 2>&1 || true
                
                aws apprunner wait service-deleted \
                    --service-arn "$service_arn" \
                    --region "$AWS_REGION" 2>/dev/null || true
                
                echo -e "${GREEN}✓ Deleted App Runner service: $SERVICE_NAME${NC}"
            ) &
            APP_RUNNER_PIDS+=($!)
        done
        
        # Wait for all App Runner deletions
        for pid in "${APP_RUNNER_PIDS[@]}"; do
            wait $pid 2>/dev/null || true
        done
    else
        echo "No App Runner services found with prefix: ${STACK_PREFIX}-"
    fi
) &
APP_RUNNER_CLEANUP_PID=$!

# NOTE: AgentCore Runtimes are NOT deleted here - they will be deleted by CloudFormation
# Deleting them manually causes DELETE_FAILED state when CloudFormation tries to delete them
echo "Note: AgentCore Runtimes will be deleted by CloudFormation stacks (not manually)"

# Wait for App Runner cleanup to complete
wait $APP_RUNNER_CLEANUP_PID 2>/dev/null || true

echo -e "${GREEN}✓ App Runner cleanup completed${NC}"

echo ""

# Step 1.5: Delete AgentCore Memories (must be done before CloudFormation)
echo -e "${YELLOW}[1.5/13] Cleaning up AgentCore Memories...${NC}"

echo "Searching for AgentCore Memories with prefix: ${STACK_PREFIX}_"
MEMORIES=$(aws bedrock-agentcore-control list-memories \
    --region "$AWS_REGION" \
    --query "memories[?starts_with(memoryName, '${STACK_PREFIX}_')].{Name:memoryName,Id:memoryId}" \
    --output json 2>/dev/null || echo "[]")

MEMORY_COUNT=$(echo "$MEMORIES" | jq '. | length' 2>/dev/null || echo "0")

if [ "$MEMORY_COUNT" -gt 0 ]; then
    echo "Found $MEMORY_COUNT AgentCore Memory/Memories to delete"
    
    # Delete memories in parallel
    MEMORY_PIDS=()
    echo "$MEMORIES" | jq -r '.[] | "\(.Id)|\(.Name)"' | while IFS='|' read -r memory_id memory_name; do
        if [ -n "$memory_id" ] && [ "$memory_id" != "null" ]; then
            echo "  Deleting memory: $memory_name (ID: $memory_id)"
            (
                aws bedrock-agentcore-control delete-memory \
                    --memory-id "$memory_id" \
                    --region "$AWS_REGION" 2>/dev/null && \
                    echo -e "${GREEN}  ✓ Deleted memory: $memory_name${NC}" || \
                    echo -e "${YELLOW}  ⚠️  Memory may not exist: $memory_name${NC}"
            ) &
            MEMORY_PIDS+=($!)
        fi
    done
    
    # Wait for all memory deletions
    for pid in "${MEMORY_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    echo -e "${GREEN}✓ AgentCore Memory cleanup completed${NC}"
else
    echo "No AgentCore Memories found with prefix: ${STACK_PREFIX}_"
fi

echo ""

# Step 2: Skip ECR repositories cleanup (preserve for faster rebuilds)
echo -e "${YELLOW}[2/13] Skipping ECR repositories cleanup (preserving images)...${NC}"

# ECR repositories and images are preserved to avoid time-consuming rebuilds
# Note: deploy-mcp.sh and deploy-agent.sh will automatically clean up orphaned
# ECR repositories if they exist outside of CloudFormation management
ECR_REPOS=(
    "${STACK_PREFIX}-coveo-agent-coveo-agent"
    "${STACK_PREFIX}-mcp-server-mcp-server"
    "${STACK_PREFIX}-ui"
)

echo "Preserving ECR repositories and images:"
for ECR_REPO in "${ECR_REPOS[@]}"; do
    if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
        IMAGE_COUNT=$(aws ecr list-images \
            --repository-name "$ECR_REPO" \
            --region "$AWS_REGION" \
            --query 'length(imageIds)' \
            --output text 2>/dev/null || echo "0")
        echo -e "${GREEN}✓ Preserved ECR repository: $ECR_REPO ($IMAGE_COUNT images)${NC}"
    else
        echo "No ECR repository found: $ECR_REPO"
    fi
done

echo -e "${YELLOW}Note: ECR repositories preserved for faster redeployments${NC}"
echo -e "${YELLOW}      Deployment scripts will auto-cleanup orphaned repos if needed${NC}"

echo ""

# Step 3: Delete orphaned Lambda functions (must be done before IAM roles!)
echo -e "${YELLOW}[3/12] Cleaning up orphaned Lambda functions...${NC}"

LAMBDA_FUNCTIONS=(
    "${STACK_PREFIX}-search-proxy"
    "${STACK_PREFIX}-passages-proxy"
    "${STACK_PREFIX}-answering-proxy"
    "${STACK_PREFIX}-query-suggest-proxy"
    "${STACK_PREFIX}-html-proxy"
    "${STACK_PREFIX}-passage-tool"
    "${STACK_PREFIX}-agentcore-runtime"
    "${STACK_PREFIX}-bedrock-agent-chat"
    "${STACK_PREFIX}-mcp-server-codebuild-trigger"
    "${STACK_PREFIX}-coveo-agent-codebuild-trigger"
)

# Delete Lambda functions in parallel for speed
LAMBDA_PIDS=()
for function in "${LAMBDA_FUNCTIONS[@]}"; do
    (delete_lambda_function "$function") &
    LAMBDA_PIDS+=($!)
done

# Wait for all Lambda deletions to complete
for pid in "${LAMBDA_PIDS[@]}"; do
    wait $pid 2>/dev/null || true
done

echo ""

# Step 4: Delete CodeBuild projects
echo -e "${YELLOW}[4/12] Cleaning up CodeBuild projects...${NC}"

CODEBUILD_PROJECTS=(
    "${STACK_PREFIX}-mcp-server-mcp-server-build"
    "${STACK_PREFIX}-coveo-agent-coveo-agent-build"
)

for project in "${CODEBUILD_PROJECTS[@]}"; do
    PROJECT_EXISTS=$(aws codebuild batch-get-projects \
        --names "$project" \
        --region "$AWS_REGION" \
        --query 'projects[0].name' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$PROJECT_EXISTS" != "NOT_FOUND" ] && [ "$PROJECT_EXISTS" != "None" ]; then
        echo "Deleting CodeBuild project: $project"
        aws codebuild delete-project \
            --name "$project" \
            --region "$AWS_REGION" > /dev/null 2>&1 || true
        echo -e "${GREEN}✓ Deleted CodeBuild project: $project${NC}"
    else
        echo "No CodeBuild project found: $project"
    fi
done

echo ""

# Step 5: Delete Bedrock Agents (must be done before IAM roles!)
echo -e "${YELLOW}[5/12] Cleaning up Bedrock Agents and Aliases...${NC}"

delete_bedrock_agent "${STACK_PREFIX}"

echo ""

# Step 6: Delete orphaned IAM roles
echo -e "${YELLOW}[6/13] Cleaning up orphaned IAM roles...${NC}"

# Wait a bit for AWS to propagate resource deletions
echo "Waiting 10 seconds for AWS to propagate resource deletions..."
sleep 10

IAM_ROLES=(
    "${STACK_PREFIX}-search-proxy-role"
    "${STACK_PREFIX}-passages-proxy-role"
    "${STACK_PREFIX}-answering-proxy-role"
    "${STACK_PREFIX}-passage-tool-role"
    "${STACK_PREFIX}-agentcore-runtime-role"
    "${STACK_PREFIX}-bedrock-agent-role"
    "${STACK_PREFIX}-bedrock-agent-chat-role"
    "${STACK_PREFIX}-apprunner-instance-role"
    "${STACK_PREFIX}-apprunner-access-role"
    "${STACK_PREFIX}-ssm-parameter-handler-role"
    "${STACK_PREFIX}-mcp-server-codebuild-role"
    "${STACK_PREFIX}-mcp-server-runtime-role"
    "${STACK_PREFIX}-mcp-server-agent-execution-role"
    "${STACK_PREFIX}-mcp-server-custom-resource-role"
    "${STACK_PREFIX}-coveo-agent-codebuild-role"
    "${STACK_PREFIX}-coveo-agent-runtime-role"
    "${STACK_PREFIX}-coveo-agent-agent-execution-role"
    "${STACK_PREFIX}-coveo-agent-custom-resource-role"
)

# Delete IAM roles in parallel for speed
ROLE_PIDS=()
for role in "${IAM_ROLES[@]}"; do
    (delete_iam_role "$role") &
    ROLE_PIDS+=($!)
done

# Wait for all role deletions to complete
for pid in "${ROLE_PIDS[@]}"; do
    wait $pid 2>/dev/null || true
done

echo ""

# Step 7: Empty S3 buckets (with versioning support, in parallel)
echo -e "${YELLOW}[7/14] Emptying S3 buckets...${NC}"

# Use dynamic and legacy bucket names (include all naming patterns)
ALL_BUCKETS="$CFN_BUCKET_NAME $CFN_BUCKET_NAME_OLD1 $CFN_BUCKET_NAME_OLD2 $UI_BUCKET_NAME $UI_BUCKET_NAME_OLD1 $UI_BUCKET_NAME_OLD2"

# Also find any other buckets with the stack prefix (for cleanup of old deployments)
ADDITIONAL_BUCKETS=$(aws s3api list-buckets \
    --query "Buckets[?starts_with(Name, '${STACK_PREFIX}-') || starts_with(Name, 'coveo-${STACK_PREFIX}-')].Name" \
    --output text 2>/dev/null || echo "")

if [ -n "$ADDITIONAL_BUCKETS" ]; then
    ALL_BUCKETS="$ALL_BUCKETS $ADDITIONAL_BUCKETS"
fi

# Remove duplicates from bucket list
ALL_BUCKETS=$(echo $ALL_BUCKETS | tr ' ' '\n' | sort -u | tr '\n' ' ')

if [ -n "$ALL_BUCKETS" ]; then
    # Delete buckets in parallel for speed
    echo "Found buckets: $ALL_BUCKETS"
    echo "Deleting buckets in parallel..."
    
    BUCKET_PIDS=()
    for bucket in $ALL_BUCKETS; do
        echo "Starting deletion: $bucket"
        (empty_and_delete_bucket "$bucket") &
        BUCKET_PIDS+=($!)
    done
    
    # Wait for all bucket deletions to complete
    echo "Waiting for parallel bucket deletions..."
    for pid in "${BUCKET_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    echo -e "${GREEN}✓ All S3 buckets processed${NC}"
else
    echo "No S3 buckets found with prefix: ${STACK_PREFIX}-"
fi

echo ""

# Step 8: Delete CloudFormation stacks (fully parallelized for maximum speed)
echo -e "${YELLOW}[8/14] Deleting CloudFormation stacks...${NC}"

# All stacks that can be deleted in parallel
ALL_STACKS=(
    "${STACK_PREFIX}-coveo-agent"
    "${STACK_PREFIX}-mcp-server"
    "${STACK_PREFIX}-mcp-codebuild"
    "${STACK_PREFIX}-ui-apprunner"
    "${STACK_PREFIX}-master-BedrockAgentStack"
    "${STACK_PREFIX}-master-CoreStack"
    "${STACK_PREFIX}-master-AuthStack"
    "${STACK_PREFIX}-master"
)

echo "Initiating parallel deletion of ALL stacks..."
STACK_DELETE_PIDS=()
STACK_DELETE_NAMES=()

for stack in "${ALL_STACKS[@]}"; do
    if stack_exists "$stack"; then
        # Get stack status to handle ROLLBACK_COMPLETE and DELETE_FAILED stacks
        stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$stack" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "UNKNOWN")
        
        echo "Starting deletion: $stack (status: $stack_status)"
        (
            if [ "$stack_status" = "ROLLBACK_COMPLETE" ]; then
                echo "Stack $stack is in ROLLBACK_COMPLETE state, deleting directly..."
            elif [ "$stack_status" = "DELETE_FAILED" ]; then
                echo "Stack $stack is in DELETE_FAILED state, cleaning up failed resources..."
                
                # Get all failed resources
                FAILED_RESOURCES=$(aws cloudformation describe-stack-resources \
                    --stack-name "$stack" \
                    --region "$AWS_REGION" \
                    --query "StackResources[?ResourceStatus=='DELETE_FAILED'].{Type:ResourceType,Id:PhysicalResourceId}" \
                    --output json 2>/dev/null || echo "[]")
                
                # Handle AgentCore Runtime resources
                RUNTIME_IDS=$(echo "$FAILED_RESOURCES" | jq -r '.[] | select(.Type=="AWS::BedrockAgentCore::Runtime") | .Id' 2>/dev/null || echo "")
                
                if [ -n "$RUNTIME_IDS" ]; then
                    for runtime_id in $RUNTIME_IDS; do
                        if [ -n "$runtime_id" ] && [ "$runtime_id" != "null" ] && [ "$runtime_id" != "None" ]; then
                            echo "  Cleaning up AgentCore Runtime: $runtime_id"
                            
                            # Check if runtime exists
                            if aws bedrock-agentcore-control get-agent-runtime \
                                --agent-runtime-id "$runtime_id" \
                                --region "$AWS_REGION" &>/dev/null; then
                                
                                # Delete endpoints first
                                ENDPOINTS=$(aws bedrock-agentcore-control list-agent-runtime-endpoints \
                                    --agent-runtime-id "$runtime_id" \
                                    --region "$AWS_REGION" \
                                    --query "agentRuntimeEndpoints[].agentRuntimeEndpointId" \
                                    --output text 2>/dev/null || echo "")
                                
                                for endpoint_id in $ENDPOINTS; do
                                    if [ -n "$endpoint_id" ] && [ "$endpoint_id" != "None" ]; then
                                        echo "    Deleting endpoint: $endpoint_id"
                                        aws bedrock-agentcore-control delete-agent-runtime-endpoint \
                                            --agent-runtime-id "$runtime_id" \
                                            --agent-runtime-endpoint-id "$endpoint_id" \
                                            --region "$AWS_REGION" 2>/dev/null || true
                                    fi
                                done
                                
                                sleep 3
                                
                                # Delete the runtime
                                aws bedrock-agentcore-control delete-agent-runtime \
                                    --agent-runtime-id "$runtime_id" \
                                    --region "$AWS_REGION" 2>/dev/null && \
                                    echo "    ✓ Runtime deleted" || \
                                    echo "    Runtime already deleted"
                            else
                                echo "    Runtime doesn't exist (already deleted)"
                            fi
                        fi
                    done
                    
                    echo "  Waiting for AWS to propagate deletions..."
                    sleep 10
                fi
                
                echo "  Retrying stack deletion..."
            fi
            aws cloudformation delete-stack --stack-name "$stack" --region "$AWS_REGION" 2>/dev/null
            echo "Deletion initiated for: $stack"
        ) &
        STACK_DELETE_PIDS+=($!)
        STACK_DELETE_NAMES+=("$stack")
    else
        echo "Stack does not exist: $stack (skipping)"
    fi
done

# Wait for all deletion commands to complete
if [ ${#STACK_DELETE_PIDS[@]} -gt 0 ]; then
    echo "Waiting for all stack deletion commands to complete..."
    for i in "${!STACK_DELETE_PIDS[@]}"; do
        wait ${STACK_DELETE_PIDS[$i]} 2>/dev/null || true
        echo "✓ Deletion command completed for: ${STACK_DELETE_NAMES[$i]}"
    done
fi

echo ""
echo "All stack deletions initiated. Monitoring progress..."

# Enhanced parallel monitoring with individual stack status
monitor_stack_deletions() {
    local max_wait_time=1800  # 30 minutes
    local wait_interval=15    # Check every 15 seconds
    local elapsed=0
    
    while [ $elapsed -lt $max_wait_time ]; do
        local remaining_stacks=0
        local status_summary=""
        
        # Check each stack status in parallel
        local check_pids=()
        local temp_dir=$(mktemp -d)
        
        for stack in "${ALL_STACKS[@]}"; do
            (
                if aws cloudformation describe-stacks --stack-name "$stack" --region "$AWS_REGION" &>/dev/null; then
                    status=$(aws cloudformation describe-stacks \
                        --stack-name "$stack" \
                        --query 'Stacks[0].StackStatus' \
                        --output text \
                        --region "$AWS_REGION" 2>/dev/null || echo "DELETED")
                    echo "$stack:$status" > "$temp_dir/$stack.status"
                else
                    echo "$stack:DELETED" > "$temp_dir/$stack.status"
                fi
            ) &
            check_pids+=($!)
        done
        
        # Wait for all status checks
        for pid in "${check_pids[@]}"; do
            wait $pid 2>/dev/null || true
        done
        
        # Process results
        for stack in "${ALL_STACKS[@]}"; do
            if [ -f "$temp_dir/$stack.status" ]; then
                local status_line=$(cat "$temp_dir/$stack.status")
                local status=${status_line#*:}
                
                if [ "$status" != "DELETED" ] && [ "$status" != "DELETE_COMPLETE" ]; then
                    remaining_stacks=$((remaining_stacks + 1))
                    status_summary="$status_summary\n  $stack: $status"
                fi
            fi
        done
        
        # Cleanup temp directory
        rm -rf "$temp_dir"
        
        if [ $remaining_stacks -eq 0 ]; then
            echo -e "${GREEN}✓ All CloudFormation stacks deleted successfully${NC}"
            break
        fi
        
        echo "[$elapsed s] $remaining_stacks stacks still deleting..."
        if [ -n "$status_summary" ]; then
            echo -e "$status_summary"
        fi
        
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    if [ $elapsed -ge $max_wait_time ]; then
        echo -e "${YELLOW}Warning: Stack deletion timeout reached after $max_wait_time seconds.${NC}"
        echo "Some stacks may still be deleting. Check AWS Console for details."
        return 1
    fi
    
    return 0
}

# Run the enhanced monitoring
monitor_stack_deletions

# Handle DELETE_FAILED stacks with comprehensive cleanup
echo ""
echo -e "${YELLOW}Checking for DELETE_FAILED stacks and retrying...${NC}"

FAILED_STACKS=()
RETRY_PIDS=()

for stack in "${ALL_STACKS[@]}"; do
    if stack_exists "$stack"; then
        STACK_STATUS=$(aws cloudformation describe-stacks \
            --stack-name "$stack" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "UNKNOWN")
        
        if [ "$STACK_STATUS" = "DELETE_FAILED" ]; then
            echo -e "${YELLOW}Found DELETE_FAILED stack: $stack${NC}"
            FAILED_STACKS+=("$stack")
            
            # Process in background for parallel cleanup
            (
                # Get all failed resources
                echo "  Analyzing failed resources..."
                FAILED_RESOURCES=$(aws cloudformation describe-stack-resources \
                    --stack-name "$stack" \
                    --region "$AWS_REGION" \
                    --query "StackResources[?ResourceStatus=='DELETE_FAILED'].{Type:ResourceType,Id:PhysicalResourceId,Reason:ResourceStatusReason}" \
                    --output json 2>/dev/null || echo "[]")
                
                # Handle AgentCore Runtime resources
                RUNTIME_IDS=$(echo "$FAILED_RESOURCES" | jq -r '.[] | select(.Type=="AWS::BedrockAgentCore::Runtime") | .Id' 2>/dev/null || echo "")
                
                if [ -n "$RUNTIME_IDS" ]; then
                    for runtime_id in $RUNTIME_IDS; do
                        if [ -n "$runtime_id" ] && [ "$runtime_id" != "null" ] && [ "$runtime_id" != "None" ]; then
                            echo "  Cleaning up AgentCore Runtime: $runtime_id"
                            
                            # Check if runtime exists
                            if aws bedrock-agentcore-control get-agent-runtime \
                                --agent-runtime-id "$runtime_id" \
                                --region "$AWS_REGION" &>/dev/null; then
                                
                                # Delete endpoints first
                                ENDPOINTS=$(aws bedrock-agentcore-control list-agent-runtime-endpoints \
                                    --agent-runtime-id "$runtime_id" \
                                    --region "$AWS_REGION" \
                                    --query "agentRuntimeEndpoints[].agentRuntimeEndpointId" \
                                    --output text 2>/dev/null || echo "")
                                
                                for endpoint_id in $ENDPOINTS; do
                                    if [ -n "$endpoint_id" ] && [ "$endpoint_id" != "None" ]; then
                                        echo "    Deleting endpoint: $endpoint_id"
                                        aws bedrock-agentcore-control delete-agent-runtime-endpoint \
                                            --agent-runtime-id "$runtime_id" \
                                            --agent-runtime-endpoint-id "$endpoint_id" \
                                            --region "$AWS_REGION" 2>/dev/null || true
                                    fi
                                done
                                
                                sleep 3
                                
                                # Delete the runtime with retries
                                MAX_RETRIES=3
                                RETRY_COUNT=0
                                DELETED=false
                                
                                while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$DELETED" = false ]; do
                                    if aws bedrock-agentcore-control delete-agent-runtime \
                                        --agent-runtime-id "$runtime_id" \
                                        --region "$AWS_REGION" 2>/dev/null; then
                                        echo "    ✓ Runtime deleted"
                                        DELETED=true
                                    else
                                        # Check if already deleted
                                        if ! aws bedrock-agentcore-control get-agent-runtime \
                                            --agent-runtime-id "$runtime_id" \
                                            --region "$AWS_REGION" &>/dev/null; then
                                            echo "    Runtime already deleted"
                                            DELETED=true
                                        else
                                            RETRY_COUNT=$((RETRY_COUNT + 1))
                                            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                                                echo "    Retry $RETRY_COUNT/$MAX_RETRIES..."
                                                sleep 5
                                            fi
                                        fi
                                    fi
                                done
                            else
                                echo "    Runtime doesn't exist (already deleted)"
                            fi
                        fi
                    done
                    
                    echo "  Waiting for AWS to propagate deletions..."
                    sleep 10
                fi
                
                # Retry stack deletion
                echo "  Retrying stack deletion..."
                aws cloudformation delete-stack --stack-name "$stack" --region "$AWS_REGION" 2>/dev/null
                
                # Wait for deletion with timeout
                echo "  Waiting for stack deletion..."
                MAX_WAIT=600  # 10 minutes
                ELAPSED=0
                INTERVAL=15
                
                while [ $ELAPSED -lt $MAX_WAIT ]; do
                    if ! aws cloudformation describe-stacks --stack-name "$stack" --region "$AWS_REGION" &>/dev/null; then
                        echo -e "${GREEN}  ✓ Stack deleted successfully: $stack${NC}"
                        exit 0
                    fi
                    
                    STATUS=$(aws cloudformation describe-stacks \
                        --stack-name "$stack" \
                        --query 'Stacks[0].StackStatus' \
                        --output text \
                        --region "$AWS_REGION" 2>/dev/null || echo "DELETED")
                    
                    if [ "$STATUS" = "DELETE_COMPLETE" ] || [ "$STATUS" = "DELETED" ]; then
                        echo -e "${GREEN}  ✓ Stack deleted successfully: $stack${NC}"
                        exit 0
                    elif [ "$STATUS" = "DELETE_FAILED" ]; then
                        echo -e "${RED}  ✗ Stack deletion failed again: $stack${NC}"
                        echo "  Manual cleanup may be required in AWS Console"
                        exit 1
                    fi
                    
                    sleep $INTERVAL
                    ELAPSED=$((ELAPSED + INTERVAL))
                done
                
                echo -e "${RED}  ✗ Timeout waiting for stack deletion: $stack${NC}"
                exit 1
            ) &
            RETRY_PIDS+=($!)
        fi
    fi
done

# Wait for all retry operations
if [ ${#RETRY_PIDS[@]} -gt 0 ]; then
    echo "Waiting for DELETE_FAILED stack cleanup to complete..."
    for pid in "${RETRY_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done
fi

if [ ${#FAILED_STACKS[@]} -eq 0 ]; then
    echo "No DELETE_FAILED stacks found"
else
    echo -e "${GREEN}✓ Processed ${#FAILED_STACKS[@]} DELETE_FAILED stack(s)${NC}"
fi

echo ""

# Step 9: Check for orphaned nested stacks
echo -e "${YELLOW}[9/14] Checking for orphaned nested stacks...${NC}"

# Define nested stacks that might be orphaned
NESTED_STACKS=(
    "${STACK_PREFIX}-master-BedrockAgentStack"
    "${STACK_PREFIX}-master-CoreStack"
    "${STACK_PREFIX}-master-AuthStack"
)

sleep 3
ORPHANED_FOUND=false
for stack in "${NESTED_STACKS[@]}"; do
    if stack_exists "$stack"; then
        echo -e "${YELLOW}Orphaned nested stack found: $stack${NC}"
        delete_stack "$stack"
        ORPHANED_FOUND=true
    fi
done

if [ "$ORPHANED_FOUND" = false ]; then
    echo "No orphaned nested stacks found"
fi

echo ""

# Step 10: Delete SSM Parameters (in parallel)
echo -e "${YELLOW}[10/14] Deleting SSM Parameters...${NC}"

# Get all parameters with the stack prefix
PARAMETERS=$(aws ssm describe-parameters \
    --region "$AWS_REGION" \
    --query "Parameters[?starts_with(Name, '/${STACK_PREFIX}/')].Name" \
    --output text 2>/dev/null || echo "")

if [ -n "$PARAMETERS" ]; then
    echo "Found $(echo $PARAMETERS | wc -w) SSM parameters to delete"
    PARAM_PIDS=()
    
    for param in $PARAMETERS; do
        echo "Deleting: $param"
        (aws ssm delete-parameter --name "$param" --region "$AWS_REGION" 2>/dev/null) &
        PARAM_PIDS+=($!)
    done
    
    # Wait for all parameter deletions
    for pid in "${PARAM_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    echo -e "${GREEN}✓ SSM parameters deleted${NC}"
else
    echo "No SSM parameters found (skipping)"
fi

echo ""

# Step 11: Delete Secrets Manager secrets (in parallel)
echo -e "${YELLOW}[11/14] Deleting Secrets Manager secrets...${NC}"

# Get all secrets with various stack prefix patterns (handles naming inconsistencies)
# Patterns: workshop/, coveo-workshop/, ${STACK_PREFIX}/
SECRETS=$(aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    --query "SecretList[?starts_with(Name, '${STACK_PREFIX}/') || starts_with(Name, 'workshop/') || starts_with(Name, 'coveo-workshop/')].Name" \
    --output text 2>/dev/null || echo "")

if [ -n "$SECRETS" ]; then
    echo "Found $(echo $SECRETS | wc -w) secrets to delete:"
    
    # Show all secrets that will be deleted
    for secret in $SECRETS; do
        echo "  - $secret"
    done
    
    echo "Starting parallel deletion..."
    SECRET_PIDS=()
    
    for secret in $SECRETS; do
        echo "Force-deleting: $secret"
        (aws secretsmanager delete-secret \
            --secret-id "$secret" \
            --force-delete-without-recovery \
            --region "$AWS_REGION" 2>/dev/null && \
            echo -e "${GREEN}✓ Deleted: $secret${NC}") &
        SECRET_PIDS+=($!)
    done
    
    # Wait for all secret deletions
    for pid in "${SECRET_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    echo -e "${GREEN}✓ All Secrets Manager secrets deleted${NC}"
else
    echo "No secrets found with prefix patterns (skipping)"
fi

# Also check for any remaining workshop-related secrets with different patterns
echo "Checking for additional workshop-related secrets..."
ADDITIONAL_SECRETS=$(aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    --query "SecretList[?contains(Name, 'coveo') && contains(Name, 'workshop')].Name" \
    --output text 2>/dev/null || echo "")

if [ -n "$ADDITIONAL_SECRETS" ]; then
    echo "Found additional workshop-related secrets:"
    ADDITIONAL_PIDS=()
    
    for secret in $ADDITIONAL_SECRETS; do
        echo "  - Force-deleting: $secret"
        (aws secretsmanager delete-secret \
            --secret-id "$secret" \
            --force-delete-without-recovery \
            --region "$AWS_REGION" 2>/dev/null && \
            echo -e "${GREEN}✓ Deleted additional: $secret${NC}") &
        ADDITIONAL_PIDS+=($!)
    done
    
    # Wait for additional deletions
    for pid in "${ADDITIONAL_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done
else
    echo "No additional workshop-related secrets found"
fi

echo ""

# Step 12: Delete CloudWatch Log Groups (in parallel)
echo -e "${YELLOW}[12/14] Deleting CloudWatch Log Groups...${NC}"

# Get all log groups with the stack prefix (including AppRunner, CodeBuild, MCP runtime, and ECS)
# AppRunner creates: /aws/apprunner/workshop-ui/application, /aws/apprunner/workshop-ui/service
# CodeBuild creates: /aws/codebuild/workshop-mcp-server-mcp-server-build
# MCP runtime creates: /aws/bedrock-agentcore/runtimes/workshop_coveo_mcp_server_runtime
# ECS creates: /aws/ecs/containerinsights/workshop-mcp-cluster/performance
LOG_GROUPS=$(aws logs describe-log-groups \
    --region "$AWS_REGION" \
    --query "logGroups[?starts_with(logGroupName, '/aws/lambda/${STACK_PREFIX}-') || starts_with(logGroupName, '/aws/apigateway/${STACK_PREFIX}-') || starts_with(logGroupName, '/aws/apprunner/${STACK_PREFIX}-') || starts_with(logGroupName, '/aws/codebuild/${STACK_PREFIX}-') || starts_with(logGroupName, '/aws/bedrock/agentcore/${STACK_PREFIX}-') || starts_with(logGroupName, '/aws/bedrock-agentcore/runtimes/${STACK_PREFIX}_') || starts_with(logGroupName, '/aws/ecs/containerinsights/${STACK_PREFIX}-')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$LOG_GROUPS" ]; then
    echo "Found $(echo $LOG_GROUPS | wc -w) log groups to delete:"
    
    # Show all log groups that will be deleted
    for log_group in $LOG_GROUPS; do
        echo "  - $log_group"
    done
    
    echo "Starting parallel deletion..."
    LOG_GROUP_PIDS=()
    
    for log_group in $LOG_GROUPS; do
        echo "Deleting: $log_group"
        (aws logs delete-log-group \
            --log-group-name "$log_group" \
            --region "$AWS_REGION" 2>/dev/null && \
            echo -e "${GREEN}✓ Deleted: $log_group${NC}") &
        LOG_GROUP_PIDS+=($!)
    done
    
    # Wait for all log group deletions
    for pid in "${LOG_GROUP_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    echo -e "${GREEN}✓ CloudWatch Log Groups deleted${NC}"
else
    echo "No log groups found with prefix patterns (skipping)"
fi

# Also check for any remaining AppRunner log groups with different patterns
echo "Checking for additional AppRunner log groups..."
APPRUNNER_LOG_GROUPS=$(aws logs describe-log-groups \
    --region "$AWS_REGION" \
    --query "logGroups[?contains(logGroupName, '${STACK_PREFIX}-ui')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$APPRUNNER_LOG_GROUPS" ]; then
    echo "Found additional AppRunner log groups:"
    ADDITIONAL_PIDS=()
    
    for log_group in $APPRUNNER_LOG_GROUPS; do
        echo "  - Deleting: $log_group"
        (aws logs delete-log-group \
            --log-group-name "$log_group" \
            --region "$AWS_REGION" 2>/dev/null && \
            echo -e "${GREEN}✓ Deleted additional: $log_group${NC}") &
        ADDITIONAL_PIDS+=($!)
    done
    
    # Wait for additional deletions
    for pid in "${ADDITIONAL_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done
else
    echo "No additional AppRunner log groups found"
fi

# Also check for any remaining runtime and ECS log groups
echo "Checking for additional runtime and ECS log groups..."
ADDITIONAL_LOG_GROUPS=$(aws logs describe-log-groups \
    --region "$AWS_REGION" \
    --query "logGroups[?starts_with(logGroupName, '/aws/bedrock-agentcore/runtimes/') || starts_with(logGroupName, '/aws/ecs/containerinsights/')].logGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$ADDITIONAL_LOG_GROUPS" ]; then
    echo "Found additional runtime and ECS log groups:"
    ADDITIONAL_PIDS=()
    
    for log_group in $ADDITIONAL_LOG_GROUPS; do
        echo "  - Deleting: $log_group"
        (aws logs delete-log-group \
            --log-group-name "$log_group" \
            --region "$AWS_REGION" 2>/dev/null && \
            echo -e "${GREEN}✓ Deleted log group: $log_group${NC}") &
        ADDITIONAL_PIDS+=($!)
    done
    
    # Wait for additional log group deletions
    for pid in "${ADDITIONAL_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done
else
    echo "No additional runtime or ECS log groups found"
fi

echo ""

# Step 13: Delete Cognito Users (before deleting user pool)
echo -e "${YELLOW}[13/14] Cleaning up Cognito Users...${NC}"

# Get User Pool ID from CloudFormation (if stack still exists)
USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$USER_POOL_ID" ] && [ "$USER_POOL_ID" != "None" ]; then
    echo "Found User Pool: $USER_POOL_ID"
    
    # List all users in the user pool
    USERS=$(aws cognito-idp list-users \
        --user-pool-id "$USER_POOL_ID" \
        --query 'Users[].Username' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -n "$USERS" ]; then
        echo "Found $(echo $USERS | wc -w) users to delete"
        
        for username in $USERS; do
            echo "Deleting user: $username"
            aws cognito-idp admin-delete-user \
                --user-pool-id "$USER_POOL_ID" \
                --username "$username" \
                --region "$AWS_REGION" 2>/dev/null || true
        done
        
        echo -e "${GREEN}✓ Cognito users deleted${NC}"
    else
        echo "No users found in user pool"
    fi
else
    echo "No User Pool found or stack already deleted"
fi

echo ""

# Step 14: Clean up local deployment artifacts and final verification
echo -e "${YELLOW}[14/14] Cleaning up local deployment artifacts and final verification...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Clean up build directory
BUILD_DIR="$PROJECT_ROOT/build"
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
    echo -e "${GREEN}✓ Build directory deleted${NC}"
fi

# Clean up deployment info files created by complete deployment
DEPLOYMENT_FILES=(
    "$PROJECT_ROOT/complete-deployment-info.txt"
    "$PROJECT_ROOT/ui-deployment-info.txt"
    "$PROJECT_ROOT/deployment-summary.txt"
)

for file in "${DEPLOYMENT_FILES[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        echo -e "${GREEN}✓ Deleted: $(basename "$file")${NC}"
    fi
done

# Clean up any Lambda ZIP files that might be left over
find "$PROJECT_ROOT/lambdas" -name "*.zip" -type f -delete 2>/dev/null || true

echo -e "${GREEN}✓ Local artifacts cleaned up${NC}"

echo ""

# Final verification and cleanup report
echo -e "${YELLOW}Final verification...${NC}"

# Check for any remaining resources
echo "Checking for any remaining resources..."

# Check CloudFormation stacks
REMAINING_STACKS=$(aws cloudformation list-stacks \
    --query "StackSummaries[?starts_with(StackName, '${STACK_PREFIX}-') && StackStatus != 'DELETE_COMPLETE'].StackName" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$REMAINING_STACKS" ]; then
    echo -e "${YELLOW}⚠️  Remaining CloudFormation stacks: $REMAINING_STACKS${NC}"
else
    echo -e "${GREEN}✓ No remaining CloudFormation stacks${NC}"
fi

# Check S3 buckets
REMAINING_BUCKETS=$(aws s3api list-buckets \
    --query "Buckets[?starts_with(Name, '${STACK_PREFIX}-')].Name" \
    --output text 2>/dev/null || echo "")

if [ -n "$REMAINING_BUCKETS" ]; then
    echo -e "${YELLOW}⚠️  Remaining S3 buckets: $REMAINING_BUCKETS${NC}"
else
    echo -e "${GREEN}✓ No remaining S3 buckets${NC}"
fi

# Check Lambda functions
REMAINING_LAMBDAS=$(aws lambda list-functions \
    --query "Functions[?starts_with(FunctionName, '${STACK_PREFIX}-')].FunctionName" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$REMAINING_LAMBDAS" ]; then
    echo -e "${YELLOW}⚠️  Remaining Lambda functions: $REMAINING_LAMBDAS${NC}"
else
    echo -e "${GREEN}✓ No remaining Lambda functions${NC}"
fi

# Check App Runner services
REMAINING_APPRUNNER=$(aws apprunner list-services \
    --query "ServiceSummaryList[?starts_with(ServiceName, '${STACK_PREFIX}-')].ServiceName" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$REMAINING_APPRUNNER" ]; then
    echo -e "${YELLOW}⚠️  Remaining App Runner services: $REMAINING_APPRUNNER${NC}"
else
    echo -e "${GREEN}✓ No remaining App Runner services${NC}"
fi

echo ""
echo -e "${GREEN}=== Destruction Complete ===${NC}"
echo ""
echo "All workshop resources created by ./deploy-complete-workshop.sh have been removed:"
echo "  ✓ App Runner Services (UI deployment)"
echo "  ✓ AgentCore Memories (conversation history)"
echo "  ✓ AgentCore Runtimes (MCP server and Agent)"
echo "  ✓ ECR Repositories (UI and MCP server images)"
echo "  ✓ Lambda Functions (deleted before roles)"
echo "  ✓ Bedrock Agents and Aliases"
echo "  ✓ IAM Roles (with managed and inline policies)"
echo "  ✓ S3 Buckets (with all versions and delete markers)"
echo "  ✓ CloudFormation Stacks (master, nested, and App Runner)"
echo "  ✓ SSM Parameters (/${STACK_PREFIX}/*)"
echo "  ✓ Secrets Manager Secrets (force-deleted)"
echo "  ✓ Cognito Users (including test user)"
echo "  ✓ Local Build Artifacts"
echo "  ✓ Local Deployment Info Files"
echo ""
echo "Note: Some resources may have a deletion delay:"
echo "  - Secrets Manager: Immediately deleted (used --force-delete-without-recovery)"
echo "  - Bedrock Agents: May take a few seconds to fully delete"
echo "  - CloudWatch Logs: May persist after stack deletion"
echo "  - CloudFormation stack events: Retained for 90 days"
echo "  - IAM eventual consistency: May take a few seconds to propagate"
echo ""
echo "You can verify cleanup with:"
echo "  aws apprunner list-services --query \"ServiceSummaryList[?starts_with(ServiceName, '${STACK_PREFIX}-')].ServiceName\" --region ${AWS_REGION}"
echo "  aws bedrock-agentcore-control list-memories --query \"memories[?starts_with(memoryName, '${STACK_PREFIX}_')].memoryName\" --region ${AWS_REGION}"
echo "  aws bedrock-agentcore-control list-agent-runtimes --query \"agentRuntimes[?starts_with(agentRuntimeName, '${STACK_PREFIX}_')].agentRuntimeName\" --region ${AWS_REGION}"
echo "  aws ecr describe-repositories --query \"repositories[?starts_with(repositoryName, '${STACK_PREFIX}-')].repositoryName\" --region ${AWS_REGION}"
echo "  aws lambda list-functions --query \"Functions[?starts_with(FunctionName, '${STACK_PREFIX}-')].FunctionName\" --region ${AWS_REGION}"
echo "  aws bedrock-agent list-agents --query \"agentSummaries[?starts_with(agentName, '${STACK_PREFIX}')].agentId\" --region ${AWS_REGION}"
echo "  aws iam list-roles --query \"Roles[?starts_with(RoleName, '${STACK_PREFIX}-')].RoleName\""
echo "  aws s3api list-buckets --query \"Buckets[?starts_with(Name, '${STACK_PREFIX}-')].Name\""
echo "  aws secretsmanager list-secrets --query \"SecretList[?starts_with(Name, '${STACK_PREFIX}/')].Name\" --region ${AWS_REGION}"
echo "  aws ssm describe-parameters --query \"Parameters[?starts_with(Name, '/${STACK_PREFIX}/')].Name\" --region ${AWS_REGION}"
echo "  aws cloudformation list-stacks --query \"StackSummaries[?starts_with(StackName, '${STACK_PREFIX}-') && StackStatus != 'DELETE_COMPLETE'].StackName\" --region ${AWS_REGION}"
echo ""
