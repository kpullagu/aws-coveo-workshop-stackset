#!/bin/bash
#
# ACTIVE REPLICATION TEST: Upload test file and verify it replicates
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_step() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
log_ok() { echo -e "${GREEN}[$(date +'%H:%M:%S')] ✅${NC} $1"; }
log_fail() { echo -e "${RED}[$(date +'%H:%M:%S')] ❌${NC} $1"; }

log_step "=========================================="
log_step "Active Replication Test"
log_step "=========================================="
echo ""

MASTER_CFN_BUCKET="${STACK_PREFIX}-${MASTER_ACCOUNT_ID}-cfn-templates"
TEST_FILE="lambdas/replication-probe-$(date +%s).txt"
TEST_CONTENT="Replication test at $(date)"

ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

# Upload test file
log_step "Uploading test file: $TEST_FILE"
echo "$TEST_CONTENT" | aws s3 cp - "s3://${MASTER_CFN_BUCKET}/${TEST_FILE}" --region "$AWS_REGION"
log_ok "Test file uploaded"

# Wait and check replication
log_step "Waiting 2 minutes for replication..."
sleep 120

SUCCESS_COUNT=0
FAIL_COUNT=0

for ACCOUNT_ID in $ACCOUNT_IDS; do
    CHILD_BUCKET="${STACK_PREFIX}-${ACCOUNT_ID}-cfn-templates"
    
    if aws s3 ls "s3://${CHILD_BUCKET}/${TEST_FILE}" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_ok "Account $ACCOUNT_ID: Test file replicated"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_fail "Account $ACCOUNT_ID: Test file NOT replicated"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
log_step "Results: $SUCCESS_COUNT succeeded, $FAIL_COUNT failed"

# Cleanup
aws s3 rm "s3://${MASTER_CFN_BUCKET}/${TEST_FILE}" --region "$AWS_REGION" 2>/dev/null || true

if [ $FAIL_COUNT -eq 0 ]; then
    log_ok "Replication is working!"
    exit 0
else
    log_fail "Replication failed for some accounts"
    exit 1
fi
