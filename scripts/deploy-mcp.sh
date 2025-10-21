#!/bin/bash

# =============================================================================
# Deploy MCP Server (Tool Provider)
# =============================================================================
# Creates AgentCore Runtime with Coveo API tools
# CloudFormation stack uses CodeBuild to generate and build Docker image
# =============================================================================

set -e

STACK_PREFIX="${STACK_PREFIX:-workshop}"
REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_PREFIX}-mcp-server"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Deploying MCP Server (Tool Provider)${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${YELLOW}What this does:${NC}"
echo -e "  → Creates AgentCore Runtime for MCP"
echo -e "  → Embeds Coveo API tool definitions"
echo -e "  → Uses CodeBuild to generate and build Docker image"
echo -e "  → Deploys to serverless AgentCore Runtime"
echo ""

# Check if CloudFormation stack exists
echo "Checking if MCP stack exists..."
STACK_EXISTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$STACK_EXISTS" = "NOT_FOUND" ]; then
    echo "Stack does not exist. Creating CloudFormation stack..."
    
    # Check for orphaned resources and clean them up
    echo "Checking for orphaned resources from previous deployments..."
    
    # 1. Check for orphaned ECR repository
    ECR_REPO_NAME="${STACK_NAME}-mcp-server"
    ECR_EXISTS=$(aws ecr describe-repositories \
        --repository-names "$ECR_REPO_NAME" \
        --region "$REGION" \
        --query 'repositories[0].repositoryName' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$ECR_EXISTS" != "NOT_FOUND" ]; then
        echo "⚠️  Found orphaned ECR repository: $ECR_REPO_NAME"
        echo "   Deleting it to allow CloudFormation to create it..."
        aws ecr delete-repository \
            --repository-name "$ECR_REPO_NAME" \
            --region "$REGION" \
            --force > /dev/null
        echo "✓ Orphaned ECR repository deleted"
    fi
    
    # 2. Check for orphaned IAM roles
    IAM_ROLES=(
        "${STACK_NAME}-codebuild-role"
        "${STACK_NAME}-runtime-role"
        "${STACK_NAME}-agent-execution-role"
        "${STACK_NAME}-custom-resource-role"
    )
    
    for ROLE_NAME in "${IAM_ROLES[@]}"; do
        ROLE_EXISTS=$(aws iam get-role \
            --role-name "$ROLE_NAME" \
            --query 'Role.RoleName' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$ROLE_EXISTS" != "NOT_FOUND" ]; then
            echo "⚠️  Found orphaned IAM role: $ROLE_NAME"
            echo "   Detaching policies and deleting role..."
            
            # Detach all managed policies
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
                --role-name "$ROLE_NAME" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            for POLICY_ARN in $ATTACHED_POLICIES; do
                aws iam detach-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-arn "$POLICY_ARN" 2>/dev/null || true
            done
            
            # Delete all inline policies
            INLINE_POLICIES=$(aws iam list-role-policies \
                --role-name "$ROLE_NAME" \
                --query 'PolicyNames[]' \
                --output text 2>/dev/null || echo "")
            
            for POLICY_NAME in $INLINE_POLICIES; do
                aws iam delete-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-name "$POLICY_NAME" 2>/dev/null || true
            done
            
            # Delete the role
            aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
            echo "✓ Orphaned IAM role deleted: $ROLE_NAME"
        fi
    done
    
    # 3. Check for orphaned CodeBuild projects
    CODEBUILD_PROJECT="${STACK_NAME}-mcp-server-build"
    PROJECT_EXISTS=$(aws codebuild batch-get-projects \
        --names "$CODEBUILD_PROJECT" \
        --region "$REGION" \
        --query 'projects[0].name' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$PROJECT_EXISTS" != "NOT_FOUND" ] && [ "$PROJECT_EXISTS" != "None" ]; then
        echo "⚠️  Found orphaned CodeBuild project: $CODEBUILD_PROJECT"
        echo "   Deleting it to allow CloudFormation to create it..."
        aws codebuild delete-project \
            --name "$CODEBUILD_PROJECT" \
            --region "$REGION" > /dev/null 2>&1 || true
        echo "✓ Orphaned CodeBuild project deleted"
    fi
    
    # 4. Check for orphaned Lambda functions
    LAMBDA_FUNCTION="${STACK_NAME}-codebuild-trigger"
    FUNCTION_EXISTS=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION" \
        --region "$REGION" \
        --query 'Configuration.FunctionName' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$FUNCTION_EXISTS" != "NOT_FOUND" ]; then
        echo "⚠️  Found orphaned Lambda function: $LAMBDA_FUNCTION"
        echo "   Deleting it to allow CloudFormation to create it..."
        aws lambda delete-function \
            --function-name "$LAMBDA_FUNCTION" \
            --region "$REGION" > /dev/null 2>&1 || true
        echo "✓ Orphaned Lambda function deleted"
    fi
    
    # 5. Check for orphaned SSM parameters
    SSM_PARAMS=(
        "/${STACK_NAME}/coveo/search-api-key"
        "/${STACK_NAME}/coveo/org-id"
        "/${STACK_NAME}/coveo/answer-config-id"
    )
    
    for PARAM_NAME in "${SSM_PARAMS[@]}"; do
        PARAM_EXISTS=$(aws ssm get-parameter \
            --name "$PARAM_NAME" \
            --region "$REGION" \
            --query 'Parameter.Name' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$PARAM_EXISTS" != "NOT_FOUND" ]; then
            echo "⚠️  Found orphaned SSM parameter: $PARAM_NAME"
            aws ssm delete-parameter \
                --name "$PARAM_NAME" \
                --region "$REGION" > /dev/null 2>&1 || true
            echo "✓ Orphaned SSM parameter deleted"
        fi
    done
    
    # 6. Check for orphaned CloudWatch Log Groups
    LOG_GROUPS=(
        "/aws/lambda/${STACK_NAME}-codebuild-trigger"
        "/aws/codebuild/${STACK_NAME}-mcp-server-build"
    )
    
    for LOG_GROUP in "${LOG_GROUPS[@]}"; do
        LOG_EXISTS=$(aws logs describe-log-groups \
            --log-group-name-prefix "$LOG_GROUP" \
            --region "$REGION" \
            --query 'logGroups[0].logGroupName' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$LOG_EXISTS" != "NOT_FOUND" ] && [ "$LOG_EXISTS" != "None" ]; then
            echo "⚠️  Found orphaned CloudWatch Log Group: $LOG_GROUP"
            aws logs delete-log-group \
                --log-group-name "$LOG_GROUP" \
                --region "$REGION" > /dev/null 2>&1 || true
            echo "✓ Orphaned CloudWatch Log Group deleted"
        fi
    done
    
    # 7. Check for orphaned AgentCore Runtime
    echo "Checking for orphaned AgentCore Runtime..."
    
    # Try to get runtime ARN from SSM
    RUNTIME_ARN=$(aws ssm get-parameter \
        --name "/${STACK_PREFIX}/coveo/mcp-runtime-arn" \
        --region "$REGION" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$RUNTIME_ARN" != "NOT_FOUND" ]; then
        echo "⚠️  Found orphaned AgentCore Runtime ARN in SSM: $RUNTIME_ARN"
        echo "   Attempting to delete the runtime..."
        
        # Try to delete the runtime
        aws bedrock-agentcore delete-runtime \
            --runtime-identifier "$RUNTIME_ARN" \
            --region "$REGION" 2>/dev/null && echo "✓ Orphaned AgentCore Runtime deleted" || echo "   Runtime may not exist or already deleted"
        
        # Delete the SSM parameter
        aws ssm delete-parameter \
            --name "/${STACK_PREFIX}/coveo/mcp-runtime-arn" \
            --region "$REGION" 2>/dev/null && echo "✓ SSM parameter deleted" || true
    fi
    
    # Also check for runtime by name pattern (in case SSM parameter doesn't exist)
    RUNTIME_NAME_PATTERN="${STACK_PREFIX}_mcp_server_coveo_mcp_tool_runtime"
    echo "Checking for runtime by name pattern: $RUNTIME_NAME_PATTERN"
    
    # List all runtimes and find matching ones
    MATCHING_RUNTIMES=$(aws bedrock-agentcore list-runtimes \
        --region "$REGION" \
        --query "runtimes[?contains(runtimeName, '${STACK_PREFIX}_mcp_server')].runtimeArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$MATCHING_RUNTIMES" ]; then
        for RUNTIME_ARN in $MATCHING_RUNTIMES; do
            echo "⚠️  Found orphaned AgentCore Runtime: $RUNTIME_ARN"
            echo "   Deleting it to allow CloudFormation to create it..."
            aws bedrock-agentcore delete-runtime \
                --runtime-identifier "$RUNTIME_ARN" \
                --region "$REGION" 2>/dev/null && echo "✓ Orphaned AgentCore Runtime deleted" || echo "   Failed to delete, may need manual cleanup"
        done
    fi
    
    echo "✓ Orphaned resources cleanup complete"
    
    # Get Cognito IDs from main stack
    echo "Getting Cognito configuration from main stack..."
    COGNITO_USER_POOL_ID=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-master" \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    COGNITO_CLIENT_ID=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-master" \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolClientId`].OutputValue' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    if [ -z "$COGNITO_USER_POOL_ID" ] || [ -z "$COGNITO_CLIENT_ID" ]; then
        echo "❌ Could not find Cognito configuration from main stack"
        echo "   Make sure ${STACK_PREFIX}-master stack is deployed first"
        exit 1
    fi
    
    echo "✓ Found Cognito User Pool ID: $COGNITO_USER_POOL_ID"
    echo "✓ Found Cognito Client ID: $COGNITO_CLIENT_ID"
    
    # Get S3 bucket for templates
    echo "Getting S3 bucket for CloudFormation templates..."
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    S3_BUCKET="${STACK_PREFIX}-${ACCOUNT_ID}-cfn-templates"
    
    # Upload template to S3 (template is too large for inline deployment)
    echo "Uploading MCP template to S3..."
    cd coveo-mcp-server
    aws s3 cp mcp-server-template.yaml "s3://${S3_BUCKET}/mcp-server-template.yaml" --region "$REGION"
    echo "✓ Template uploaded to s3://${S3_BUCKET}/mcp-server-template.yaml"
    
    # Create CloudFormation stack using S3 template URL
    echo "Creating MCP CloudFormation stack..."
    TEMPLATE_URL="https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/mcp-server-template.yaml"
    
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-url "$TEMPLATE_URL" \
        --parameters \
            ParameterKey=StackPrefix,ParameterValue="$STACK_PREFIX" \
            ParameterKey=CognitoUserPoolId,ParameterValue="$COGNITO_USER_POOL_ID" \
            ParameterKey=CognitoUserPoolClientId,ParameterValue="$COGNITO_CLIENT_ID" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" > /dev/null
    
    echo "✓ Stack creation initiated"
    
    # Wait for stack creation
    echo "Waiting for stack creation to complete (this may take 10-15 minutes)..."
    echo "CloudFormation will automatically:"
    echo "  • Create ECR repository"
    echo "  • Generate MCP server code (inline in BuildSpec)"
    echo "  • Build Docker image via CodeBuild"
    echo "  • Push image to ECR"
    echo "  • Deploy AgentCore Runtime"
    
    aws cloudformation wait stack-create-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
    
    echo "✓ Stack created successfully"
    cd ..
else
    echo "✓ Stack already exists"
    echo ""
    echo "To update the MCP server code:"
    echo "  1. Edit the inline code in coveo-mcp-server/mcp-server-template.yaml"
    echo "  2. Upload template to S3 and update the stack:"
    
    # Get S3 bucket and upload template
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    S3_BUCKET="${STACK_PREFIX}-${ACCOUNT_ID}-cfn-templates"
    
    cd coveo-mcp-server
    echo "Uploading updated template to S3..."
    aws s3 cp mcp-server-template.yaml "s3://${S3_BUCKET}/mcp-server-template.yaml" --region "$REGION"
    
    TEMPLATE_URL="https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/mcp-server-template.yaml"
    
    echo "Updating CloudFormation stack..."
    aws cloudformation update-stack \
        --stack-name "$STACK_NAME" \
        --template-url "$TEMPLATE_URL" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
    
    echo "✓ Stack update initiated"
    echo "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
    
    echo "✓ Stack updated successfully"
    cd ..
fi

# Get MCP runtime ARN from CloudFormation outputs
echo "Getting MCP runtime ARN..."
MCP_RUNTIME_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`MCPServerRuntimeArn`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -z "$MCP_RUNTIME_ARN" ]; then
    echo "❌ MCP runtime ARN not found in stack outputs"
    exit 1
fi

echo "✓ MCP Runtime ARN: $MCP_RUNTIME_ARN"

# Write MCP runtime ARN to SSM
echo "Writing MCP runtime ARN to SSM..."
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/coveo/mcp-runtime-arn" \
    --value "$MCP_RUNTIME_ARN" \
    --type String \
    --overwrite \
    --region "$REGION" > /dev/null

echo "✓ MCP runtime ARN saved to SSM: /${STACK_PREFIX}/coveo/mcp-runtime-arn"

# Also get and save the MCP runtime URL for direct access if needed
MCP_RUNTIME_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`MCPServerRuntimeId`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -n "$MCP_RUNTIME_ID" ]; then
    # Construct the MCP invocation URL
    ENCODED_ARN=$(echo "$MCP_RUNTIME_ARN" | sed 's/:/%3A/g' | sed 's/\//%2F/g')
    MCP_URL="https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/${ENCODED_ARN}/invocations?qualifier=DEFAULT"
    
    aws ssm put-parameter \
        --name "/${STACK_PREFIX}/coveo/mcp-url" \
        --value "$MCP_URL" \
        --type String \
        --overwrite \
        --region "$REGION" > /dev/null
    
    echo "✓ MCP URL saved to SSM: /${STACK_PREFIX}/coveo/mcp-url"
fi

echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}✅ MCP Server Deployment Complete${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${YELLOW}What was deployed:${NC}"
echo -e "  ✓ AgentCore Runtime for MCP"
echo -e "  ✓ Docker image built and pushed to ECR"
echo -e "  ✓ Coveo API tools configured"
echo -e "  ✓ Runtime ARN saved to SSM"
echo ""
echo -e "${BLUE}MCP Runtime ARN: $MCP_RUNTIME_ARN${NC}"
echo -e "${BLUE}MCP Runtime ID: $MCP_RUNTIME_ID${NC}"
echo ""
