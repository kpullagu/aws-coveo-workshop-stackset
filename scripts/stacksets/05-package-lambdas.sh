#!/bin/bash
#
# Package all Lambda functions and upload to master S3
#

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Ensure we're in the project root
cd "$SCRIPT_DIR/../.."

log_info "=========================================="
log_info "Packaging Lambda Functions"
log_info "=========================================="
log_info "Working directory: $(pwd)"

# Create master S3 bucket if it doesn't exist
MASTER_CFN_BUCKET="${STACK_PREFIX}-${MASTER_ACCOUNT_ID}-cfn-templates"

log_info "Checking master S3 bucket: $MASTER_CFN_BUCKET"
if ! aws s3 ls "s3://${MASTER_CFN_BUCKET}" --region "$AWS_REGION" 2>/dev/null; then
    log_info "Creating master S3 bucket..."
    aws s3 mb "s3://${MASTER_CFN_BUCKET}" --region "$AWS_REGION"
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$MASTER_CFN_BUCKET" \
        --versioning-configuration Status=Enabled \
        --region "$AWS_REGION"
fi

# Lambda functions to package
LAMBDA_DIRS=(
    "lambdas/search_proxy"
    "lambdas/passages_proxy"
    "lambdas/answering_proxy"
    "lambdas/query_suggest_proxy"
    "lambdas/html_proxy"
    "lambdas/coveo_passage_tool_py"
    "lambdas/agentcore_runtime_py"
    "lambdas/bedrock_agent_chat"
)

# Save current directory
PROJECT_ROOT=$(pwd)

for LAMBDA_DIR in "${LAMBDA_DIRS[@]}"; do
    if [ ! -d "$PROJECT_ROOT/$LAMBDA_DIR" ]; then
        log_warning "Lambda directory not found: $LAMBDA_DIR, skipping..."
        continue
    fi
    
    LAMBDA_NAME=$(basename "$LAMBDA_DIR")
    log_info "Packaging $LAMBDA_NAME..."
    
    # Create package directory
    mkdir -p "$PROJECT_ROOT/$LAMBDA_DIR/package"
    
    # Copy Lambda code
    if [ -f "$PROJECT_ROOT/$LAMBDA_DIR/lambda_function.py" ]; then
        cp "$PROJECT_ROOT/$LAMBDA_DIR/lambda_function.py" "$PROJECT_ROOT/$LAMBDA_DIR/package/"
    fi
    
    # Copy config module if exists
    if [ -d "$PROJECT_ROOT/config" ]; then
        cp -r "$PROJECT_ROOT/config" "$PROJECT_ROOT/$LAMBDA_DIR/package/" 2>/dev/null || true
    fi
    
    # Create ZIP file
    cd "$PROJECT_ROOT/$LAMBDA_DIR/package"
    zip -r "../${LAMBDA_NAME}.zip" . -q
    cd "$PROJECT_ROOT"
    
    # Upload to S3
    aws s3 cp "$PROJECT_ROOT/$LAMBDA_DIR/${LAMBDA_NAME}.zip" \
        "s3://${MASTER_CFN_BUCKET}/lambdas/${LAMBDA_NAME}.zip" \
        --region "$AWS_REGION"
    
    log_success "Packaged and uploaded $LAMBDA_NAME"
    
    # Clean up
    rm -rf "$PROJECT_ROOT/$LAMBDA_DIR/package"
    rm -f "$PROJECT_ROOT/$LAMBDA_DIR/${LAMBDA_NAME}.zip"
done

echo ""
log_success "All Lambda functions packaged and uploaded!"
echo "S3 Bucket: s3://${MASTER_CFN_BUCKET}/lambdas/"
