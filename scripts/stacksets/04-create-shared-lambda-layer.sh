#!/bin/bash
#
# Create shared Lambda layer in master account
#

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Ensure we're in the project root
cd "$SCRIPT_DIR/../.."

log_info "=========================================="
log_info "Creating Shared Lambda Layer"
log_info "=========================================="
log_info "Master Account: $MASTER_ACCOUNT_ID"
log_info "Region: $AWS_REGION"
echo ""

# Create layer directory
LAYER_DIR="lambda-layer"
mkdir -p "$LAYER_DIR/python"

# Install dependencies from all Lambda functions
log_info "Installing Python dependencies..."

# Create a unified requirements file with compatible versions
log_info "Creating unified requirements file..."
cat > "$LAYER_DIR/python/requirements.txt" << EOF
# Unified dependencies for all Lambda functions
# Using compatible versions to avoid conflicts

# Core AWS and HTTP libraries
boto3>=1.28.0
requests>=2.28.0
urllib3>=1.26.0,<2.0.0

# X-Ray SDK for observability
aws-xray-sdk>=2.12.0
EOF

# Install all dependencies
log_info "Installing all dependencies..."
pip install -r "$LAYER_DIR/python/requirements.txt" -t "$LAYER_DIR/python" --quiet --upgrade

# Create ZIP file
log_info "Creating layer ZIP file..."
cd "$LAYER_DIR"
zip -r ../lambda-layer.zip . -q
cd ..

# Publish layer
log_info "Publishing Lambda layer..."
LAYER_ARN=$(aws lambda publish-layer-version \
    --layer-name "${STACK_PREFIX}-shared-dependencies" \
    --description "Shared dependencies for workshop Lambda functions" \
    --zip-file fileb://lambda-layer.zip \
    --compatible-runtimes python3.12 \
    --region "$AWS_REGION" \
    --query 'LayerVersionArn' \
    --output text)

log_success "Lambda layer published: $LAYER_ARN"

# Store ARN in SSM
log_info "Storing layer ARN in SSM..."
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/lambda-layer-arn" \
    --value "$LAYER_ARN" \
    --type "String" \
    --overwrite \
    --description "Shared Lambda layer ARN" \
    --region "$AWS_REGION" >/dev/null

log_success "Layer ARN stored in SSM: /${STACK_PREFIX}/lambda-layer-arn"

# Grant permission to child accounts
log_info "Granting layer access to child accounts..."
LAYER_VERSION=$(echo $LAYER_ARN | rev | cut -d: -f1 | rev)

# Get all child account IDs
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text 2>/dev/null || echo "")

if [ -n "$ACCOUNT_IDS" ]; then
    COUNTER=1
    for ACCOUNT_ID in $ACCOUNT_IDS; do
        STATEMENT_ID="AllowAccount${ACCOUNT_ID}"
        
        aws lambda add-layer-version-permission \
            --layer-name "${STACK_PREFIX}-shared-dependencies" \
            --version-number "$LAYER_VERSION" \
            --statement-id "$STATEMENT_ID" \
            --action lambda:GetLayerVersion \
            --principal "$ACCOUNT_ID" \
            --region "$AWS_REGION" \
            >/dev/null 2>&1 && log_info "  ✓ Permission added for account $ACCOUNT_ID" || log_info "  ℹ Permission exists for account $ACCOUNT_ID"
        
        COUNTER=$((COUNTER + 1))
    done
    log_success "Permissions granted to all child accounts"
else
    log_warning "No child accounts found in OU $OU_ID"
fi

# Cleanup
rm -rf "$LAYER_DIR" lambda-layer.zip

echo ""
log_success "Shared Lambda layer created successfully!"
echo "Layer ARN: $LAYER_ARN"
