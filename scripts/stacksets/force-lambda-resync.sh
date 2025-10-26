#!/bin/bash
#
# Force re-upload of all Lambda packages to trigger replication
# Use this after setting up replication to ensure all packages replicate
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_step() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
log_ok() { echo -e "${GREEN}[$(date +'%H:%M:%S')] ✅${NC} $1"; }

log_step "=========================================="
log_step "Force Lambda Package Re-sync"
log_step "=========================================="
echo ""

MASTER_CFN_BUCKET="${STACK_PREFIX}-${MASTER_ACCOUNT_ID}-cfn-templates"

log_step "This will re-upload all Lambda packages to trigger replication"
log_step "Master bucket: $MASTER_CFN_BUCKET"
echo ""

# Get list of existing packages
PACKAGES=$(aws s3 ls "s3://${MASTER_CFN_BUCKET}/lambdas/" --region "$AWS_REGION" | awk '{print $4}' | grep ".zip$" || echo "")

if [ -z "$PACKAGES" ]; then
    log_step "No packages found, running full package script..."
    bash "$SCRIPT_DIR/05-package-lambdas.sh"
    exit 0
fi

PACKAGE_COUNT=$(echo "$PACKAGES" | wc -l)
log_step "Found $PACKAGE_COUNT packages to re-upload"
echo ""

# Download and re-upload each package
TEMP_DIR="/tmp/lambda-resync-$$"
mkdir -p "$TEMP_DIR"

for PACKAGE in $PACKAGES; do
    log_step "Re-uploading: $PACKAGE"
    
    # Download
    aws s3 cp "s3://${MASTER_CFN_BUCKET}/lambdas/${PACKAGE}" "$TEMP_DIR/${PACKAGE}" --region "$AWS_REGION" --quiet
    
    # Re-upload (creates new version, triggers replication)
    aws s3 cp "$TEMP_DIR/${PACKAGE}" "s3://${MASTER_CFN_BUCKET}/lambdas/${PACKAGE}" --region "$AWS_REGION" --quiet
    
    log_ok "Re-uploaded: $PACKAGE"
done

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
log_ok "All $PACKAGE_COUNT packages re-uploaded"
log_step "Replication should start automatically"
log_step "Wait 5-15 minutes for replication to complete"
echo ""
