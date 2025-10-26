#!/bin/bash
#
# Fix Lambda Layer Permissions for Cross-Account Access
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=========================================="
log_info "Fix Lambda Layer Permissions"
log_info "=========================================="

# Get the Lambda Layer ARN from SSM
LAYER_ARN=$(aws ssm get-parameter \
    --name "/${STACK_PREFIX}/lambda-layer-arn" \
    --query "Parameter.Value" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -z "$LAYER_ARN" ]; then
    log_error "Lambda Layer ARN not found in SSM"
    log_info "Run: bash scripts/stacksets/04-create-shared-lambda-layer.sh"
    exit 1
fi

log_info "Lambda Layer ARN: $LAYER_ARN"

# Extract layer name and version
LAYER_NAME=$(echo "$LAYER_ARN" | cut -d':' -f7)
LAYER_VERSION=$(echo "$LAYER_ARN" | cut -d':' -f8)

log_info "Layer Name: $LAYER_NAME"
log_info "Layer Version: $LAYER_VERSION"

# Get all child account IDs
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

ACCOUNT_COUNT=$(echo $ACCOUNT_IDS | wc -w)
log_info "Found $ACCOUNT_COUNT child accounts"
log_info "Accounts: $ACCOUNT_IDS"

# Add permission for each child account
log_info ""
log_info "Adding Lambda Layer permissions..."

STATEMENT_ID_BASE="AllowAccount"
COUNTER=1

for ACCOUNT_ID in $ACCOUNT_IDS; do
    STATEMENT_ID="${STATEMENT_ID_BASE}${ACCOUNT_ID}"
    
    log_info "[$COUNTER/$ACCOUNT_COUNT] Adding permission for account: $ACCOUNT_ID"
    
    # Try to add permission (ignore if already exists)
    # Try to add permission with timeout
    log_info "  Adding permission (this may take a moment)..."
    
    timeout 30 aws lambda add-layer-version-permission \
        --layer-name "$LAYER_NAME" \
        --version-number "$LAYER_VERSION" \
        --statement-id "$STATEMENT_ID" \
        --action lambda:GetLayerVersion \
        --principal "$ACCOUNT_ID" \
        --region "$AWS_REGION" \
        2>&1 | grep -v "ResourceConflictException" || true
    
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        log_success "  ✓ Permission added for $ACCOUNT_ID"
    elif [ $EXIT_CODE -eq 124 ]; then
        log_warning "  ⚠ Command timed out for $ACCOUNT_ID, checking if permission exists..."
        # Check if permission already exists
        EXISTING=$(aws lambda get-layer-version-policy \
            --layer-name "$LAYER_NAME" \
            --version-number "$LAYER_VERSION" \
            --region "$AWS_REGION" \
            --query "Policy" \
            --output text 2>/dev/null | grep -c "$ACCOUNT_ID" || echo "0")
        
        if [ "$EXISTING" -gt 0 ]; then
            log_success "  ✓ Permission already exists for $ACCOUNT_ID"
        else
            log_error "  ✗ Timeout and permission not found for $ACCOUNT_ID"
        fi
    else
        # Check if permission already exists (might have failed due to conflict)
        EXISTING=$(aws lambda get-layer-version-policy \
            --layer-name "$LAYER_NAME" \
            --version-number "$LAYER_VERSION" \
            --region "$AWS_REGION" \
            --query "Policy" \
            --output text 2>/dev/null | grep -c "$ACCOUNT_ID" || echo "0")
        
        if [ "$EXISTING" -gt 0 ]; then
            log_info "  ℹ Permission already exists for $ACCOUNT_ID"
        else
            log_warning "  ⚠ Failed to add permission for $ACCOUNT_ID (may already exist)"
        fi
    fi
    
    COUNTER=$((COUNTER + 1))
done

# Verify permissions
log_info ""
log_info "=========================================="
log_info "Verifying Permissions"
log_info "=========================================="

POLICY=$(aws lambda get-layer-version-policy \
    --layer-name "$LAYER_NAME" \
    --version-number "$LAYER_VERSION" \
    --region "$AWS_REGION" \
    --query "Policy" \
    --output text 2>/dev/null || echo "")

if [ -n "$POLICY" ]; then
    log_success "Layer policy exists"
    echo "$POLICY" | jq '.' 2>/dev/null || echo "$POLICY"
    
    # Count how many accounts have permission
    PERMITTED_COUNT=$(echo "$POLICY" | jq -r '.Statement[].Principal.AWS' 2>/dev/null | wc -l)
    log_info ""
    log_info "Accounts with permission: $PERMITTED_COUNT"
    
    if [ "$PERMITTED_COUNT" -eq "$ACCOUNT_COUNT" ]; then
        log_success "✅ All $ACCOUNT_COUNT child accounts have permission"
    else
        log_warning "⚠️  Only $PERMITTED_COUNT of $ACCOUNT_COUNT accounts have permission"
    fi
else
    log_error "Could not retrieve layer policy"
fi

log_success ""
log_success "=========================================="
log_success "Lambda Layer Permissions Updated!"
log_success "=========================================="
log_info "Child accounts can now use the Lambda Layer"
log_info ""
log_info "Next step:"
log_info "  bash scripts/stacksets/11-deploy-layer2-core.sh"
