#!/bin/bash
#
# IMPROVED: Setup S3 cross-account replication with comprehensive verification
# This ensures replication works reliably every time
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Color codes for better visibility
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Enhanced logging with timestamps
log_step() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $1"
}

log_fail() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"
}

log_step "=========================================="
log_step "S3 Cross-Account Replication Setup (Enhanced)"
log_step "=========================================="
echo ""

# Configuration
MASTER_CFN_BUCKET="${STACK_PREFIX}-${MASTER_ACCOUNT_ID}-cfn-templates"
REPLICATION_ROLE_NAME="${STACK_PREFIX}-s3-replication-role"

# Get all child account IDs
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

ACCOUNT_COUNT=$(echo $ACCOUNT_IDS | wc -w)

log_step "Configuration:"
echo "  Master Account: $MASTER_ACCOUNT_ID"
echo "  Master Bucket: $MASTER_CFN_BUCKET"
echo "  Target Accounts: $ACCOUNT_COUNT"
echo "  Accounts: $ACCOUNT_IDS"
echo ""

# ============================================================================
# STEP 1: Pre-flight checks
# ============================================================================
log_step "Step 1: Pre-flight checks"
echo ""

# Check 1.1: Master bucket exists
log_step "  1.1: Checking master bucket exists..."
if aws s3 ls "s3://${MASTER_CFN_BUCKET}" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_ok "Master bucket exists"
else
    log_fail "Master bucket NOT found: $MASTER_CFN_BUCKET"
    log_fail "Run: bash scripts/stacksets/01-setup-master-ecr.sh"
    exit 1
fi

# Check 1.2: Master bucket versioning
log_step "  1.2: Checking master bucket versioning..."
MASTER_VERSIONING=$(aws s3api get-bucket-versioning \
    --bucket "$MASTER_CFN_BUCKET" \
    --region "$AWS_REGION" \
    --query 'Status' \
    --output text 2>/dev/null || echo "")

if [ "$MASTER_VERSIONING" = "Enabled" ]; then
    log_ok "Master bucket versioning enabled"
else
    log_warn "Master bucket versioning NOT enabled, enabling now..."
    aws s3api put-bucket-versioning \
        --bucket "$MASTER_CFN_BUCKET" \
        --versioning-configuration Status=Enabled \
        --region "$AWS_REGION"
    log_ok "Master bucket versioning enabled"
fi

# Check 1.3: Child buckets exist (via Layer 1 StackSet)
log_step "  1.3: Checking child buckets exist..."
LAYER1_MISSING=0

for ACCOUNT_ID in $ACCOUNT_IDS; do
    INSTANCE_STATUS=$(aws cloudformation list-stack-instances \
        --stack-set-name "workshop-layer1-prerequisites" \
        --stack-instance-account "$ACCOUNT_ID" \
        --stack-instance-region "$AWS_REGION" \
        --region "$AWS_REGION" \
        --query 'Summaries[0].Status' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$INSTANCE_STATUS" = "CURRENT" ]; then
        log_ok "Account $ACCOUNT_ID: Layer 1 is CURRENT"
    else
        log_fail "Account $ACCOUNT_ID: Layer 1 status is $INSTANCE_STATUS"
        LAYER1_MISSING=1
    fi
done

if [ $LAYER1_MISSING -eq 1 ]; then
    log_fail "Some child buckets are not ready"
    log_fail "Deploy Layer 1 first: bash scripts/stacksets/10-deploy-layer1-prerequisites.sh"
    exit 1
fi

echo ""

# ============================================================================
# STEP 2: Create/Update IAM Replication Role
# ============================================================================
log_step "Step 2: Creating/Updating IAM replication role"
echo ""

# Check if role exists
if aws iam get-role --role-name "$REPLICATION_ROLE_NAME" >/dev/null 2>&1; then
    log_step "  Role already exists, updating..."
    ROLE_EXISTS=true
else
    log_step "  Creating new role..."
    ROLE_EXISTS=false
fi

# Trust policy
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "s3.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF
)

if [ "$ROLE_EXISTS" = false ]; then
    aws iam create-role \
        --role-name "$REPLICATION_ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "S3 replication role for cross-account Lambda package distribution"
    log_ok "Replication role created"
else
    aws iam update-assume-role-policy \
        --role-name "$REPLICATION_ROLE_NAME" \
        --policy-document "$TRUST_POLICY"
    log_ok "Replication role trust policy updated"
fi

# Build destination bucket ARNs
DEST_BUCKET_ARNS=""
for ACCOUNT_ID in $ACCOUNT_IDS; do
    DEST_BUCKET="arn:aws:s3:::${STACK_PREFIX}-${ACCOUNT_ID}-cfn-templates"
    if [ -z "$DEST_BUCKET_ARNS" ]; then
        DEST_BUCKET_ARNS="\"$DEST_BUCKET\", \"$DEST_BUCKET/*\""
    else
        DEST_BUCKET_ARNS="$DEST_BUCKET_ARNS, \"$DEST_BUCKET\", \"$DEST_BUCKET/*\""
    fi
done

# Replication policy
REPLICATION_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetReplicationConfiguration", "s3:ListBucket"],
      "Resource": "arn:aws:s3:::${MASTER_CFN_BUCKET}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Resource": "arn:aws:s3:::${MASTER_CFN_BUCKET}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags",
        "s3:ObjectOwnerOverrideToBucketOwner"
      ],
      "Resource": [$DEST_BUCKET_ARNS]
    }
  ]
}
EOF
)

POLICY_NAME="${REPLICATION_ROLE_NAME}-policy"

# Delete existing policy
aws iam delete-role-policy \
    --role-name "$REPLICATION_ROLE_NAME" \
    --policy-name "$POLICY_NAME" 2>/dev/null || true

# Attach new policy
aws iam put-role-policy \
    --role-name "$REPLICATION_ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document "$REPLICATION_POLICY"

log_ok "Replication policy attached"

# Wait for IAM propagation
log_step "  Waiting 15 seconds for IAM role to propagate..."
sleep 15

echo ""

# ============================================================================
# STEP 3: Configure Replication Rules
# ============================================================================
log_step "Step 3: Configuring replication rules"
echo ""

# Build replication rules with unique IDs and priorities
REPLICATION_RULES=""
RULE_ID=1

for ACCOUNT_ID in $ACCOUNT_IDS; do
    DEST_BUCKET="${STACK_PREFIX}-${ACCOUNT_ID}-cfn-templates"
    
    RULE=$(cat <<EOF
    {
      "ID": "ReplicateToAccount${ACCOUNT_ID}",
      "Priority": $RULE_ID,
      "Filter": {"Prefix": "lambdas/"},
      "Status": "Enabled",
      "Destination": {
        "Bucket": "arn:aws:s3:::${DEST_BUCKET}",
        "ReplicationTime": {
          "Status": "Enabled",
          "Time": {"Minutes": 15}
        },
        "Metrics": {
          "Status": "Enabled",
          "EventThreshold": {"Minutes": 15}
        },
        "AccessControlTranslation": {"Owner": "Destination"},
        "Account": "${ACCOUNT_ID}"
      },
      "DeleteMarkerReplication": {"Status": "Disabled"}
    }
EOF
)
    
    if [ -z "$REPLICATION_RULES" ]; then
        REPLICATION_RULES="$RULE"
    else
        REPLICATION_RULES="$REPLICATION_RULES,$RULE"
    fi
    
    log_step "  Added rule for account $ACCOUNT_ID (Priority: $RULE_ID)"
    RULE_ID=$((RULE_ID + 1))
done

# Create replication configuration
REPLICATION_CONFIG=$(cat <<EOF
{
  "Role": "arn:aws:iam::${MASTER_ACCOUNT_ID}:role/${REPLICATION_ROLE_NAME}",
  "Rules": [$REPLICATION_RULES]
}
EOF
)

# Apply replication configuration
echo "$REPLICATION_CONFIG" > /tmp/replication-config.json

aws s3api put-bucket-replication \
    --bucket "$MASTER_CFN_BUCKET" \
    --replication-configuration file:///tmp/replication-config.json \
    --region "$AWS_REGION"

rm /tmp/replication-config.json

log_ok "Replication rules configured ($ACCOUNT_COUNT rules)"

echo ""

# ============================================================================
# STEP 4: Verify Replication Configuration
# ============================================================================
log_step "Step 4: Verifying replication configuration"
echo ""

# Verify rules exist
CONFIGURED_RULES=$(aws s3api get-bucket-replication \
    --bucket "$MASTER_CFN_BUCKET" \
    --region "$AWS_REGION" \
    --query 'length(ReplicationConfiguration.Rules)' \
    --output text 2>/dev/null || echo "0")

if [ "$CONFIGURED_RULES" -eq "$ACCOUNT_COUNT" ]; then
    log_ok "All $ACCOUNT_COUNT replication rules configured"
else
    log_fail "Expected $ACCOUNT_COUNT rules, found $CONFIGURED_RULES"
    exit 1
fi

# Verify role ARN matches
CONFIGURED_ROLE=$(aws s3api get-bucket-replication \
    --bucket "$MASTER_CFN_BUCKET" \
    --region "$AWS_REGION" \
    --query 'ReplicationConfiguration.Role' \
    --output text 2>/dev/null || echo "")

EXPECTED_ROLE="arn:aws:iam::${MASTER_ACCOUNT_ID}:role/${REPLICATION_ROLE_NAME}"

if [ "$CONFIGURED_ROLE" = "$EXPECTED_ROLE" ]; then
    log_ok "Replication role ARN matches"
else
    log_fail "Role ARN mismatch!"
    log_fail "  Expected: $EXPECTED_ROLE"
    log_fail "  Found: $CONFIGURED_ROLE"
    exit 1
fi

# Show rules
log_step "  Configured rules:"
aws s3api get-bucket-replication \
    --bucket "$MASTER_CFN_BUCKET" \
    --region "$AWS_REGION" \
    --query 'ReplicationConfiguration.Rules[*].[ID,Status,Priority,Destination.Account]' \
    --output table

echo ""
log_ok "=========================================="
log_ok "S3 Replication Setup Complete!"
log_ok "=========================================="
echo ""
log_step "Summary:"
echo "  ✅ Master bucket versioning: Enabled"
echo "  ✅ Replication role: $REPLICATION_ROLE_NAME"
echo "  ✅ Replication rules: $ACCOUNT_COUNT configured"
echo "  ✅ Filter: lambdas/*"
echo "  ✅ Replication time: 15 minutes SLA"
echo ""
log_step "Next steps:"
echo "  1. Upload Lambda packages (or re-upload to trigger replication)"
echo "  2. Run active replication test"
echo "  3. Wait for replication to complete"
echo "  4. Deploy Layer 2"
echo ""
