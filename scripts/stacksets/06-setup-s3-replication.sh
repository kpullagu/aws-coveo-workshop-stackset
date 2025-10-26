#!/bin/bash
#
# Setup S3 replication from master account to all child accounts
# This creates the replication role and configures replication rules
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=========================================="
log_info "Setting up S3 Cross-Account Replication"
log_info "=========================================="

# Master bucket
MASTER_CFN_BUCKET="${STACK_PREFIX}-${MASTER_ACCOUNT_ID}-cfn-templates"
REPLICATION_ROLE_NAME="${STACK_PREFIX}-s3-replication-role"

# Get all child account IDs
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

ACCOUNT_COUNT=$(echo $ACCOUNT_IDS | wc -w)
log_info "Master Account: $MASTER_ACCOUNT_ID"
log_info "Master Bucket: $MASTER_CFN_BUCKET"
log_info "Target Accounts ($ACCOUNT_COUNT): $ACCOUNT_IDS"
echo ""

# Step 1: Create IAM replication role in master account
log_info "Step 1: Creating S3 replication IAM role..."

# Check if role already exists
if aws iam get-role --role-name "$REPLICATION_ROLE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_info "Replication role already exists, updating..."
    ROLE_EXISTS=true
else
    log_info "Creating new replication role..."
    ROLE_EXISTS=false
fi

# Create trust policy
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

if [ "$ROLE_EXISTS" = false ]; then
    aws iam create-role \
        --role-name "$REPLICATION_ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "S3 replication role for cross-account Lambda package distribution" \
        --region "$AWS_REGION"
    log_success "✓ Replication role created"
else
    aws iam update-assume-role-policy \
        --role-name "$REPLICATION_ROLE_NAME" \
        --policy-document "$TRUST_POLICY" \
        --region "$AWS_REGION"
    log_success "✓ Replication role trust policy updated"
fi

# Step 2: Create replication policy
log_info "Step 2: Creating replication policy..."

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

# Create replication policy
REPLICATION_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
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
      "Resource": [
        $DEST_BUCKET_ARNS
      ]
    }
  ]
}
EOF
)

POLICY_NAME="${REPLICATION_ROLE_NAME}-policy"

# Delete existing policy if it exists
aws iam delete-role-policy \
    --role-name "$REPLICATION_ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --region "$AWS_REGION" 2>/dev/null || true

# Attach new policy
aws iam put-role-policy \
    --role-name "$REPLICATION_ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document "$REPLICATION_POLICY" \
    --region "$AWS_REGION"

log_success "✓ Replication policy attached"

# Wait for IAM role to propagate
log_info "Waiting 10 seconds for IAM role to propagate..."
sleep 10

# Step 3: Configure replication on master bucket
log_info "Step 3: Configuring replication rules on master bucket..."

# Build replication rules
REPLICATION_RULES=""
RULE_ID=1

for ACCOUNT_ID in $ACCOUNT_IDS; do
    DEST_BUCKET="${STACK_PREFIX}-${ACCOUNT_ID}-cfn-templates"
    
    RULE=$(cat <<EOF
    {
      "ID": "ReplicateToAccount${ACCOUNT_ID}",
      "Priority": $RULE_ID,
      "Filter": {
        "Prefix": "lambdas/"
      },
      "Status": "Enabled",
      "Destination": {
        "Bucket": "arn:aws:s3:::${DEST_BUCKET}",
        "ReplicationTime": {
          "Status": "Enabled",
          "Time": {
            "Minutes": 15
          }
        },
        "Metrics": {
          "Status": "Enabled",
          "EventThreshold": {
            "Minutes": 15
          }
        },
        "AccessControlTranslation": {
          "Owner": "Destination"
        },
        "Account": "${ACCOUNT_ID}"
      },
      "DeleteMarkerReplication": {
        "Status": "Disabled"
      }
    }
EOF
)
    
    if [ -z "$REPLICATION_RULES" ]; then
        REPLICATION_RULES="$RULE"
    else
        REPLICATION_RULES="$REPLICATION_RULES,$RULE"
    fi
    
    RULE_ID=$((RULE_ID + 1))
done

# Create replication configuration
REPLICATION_CONFIG=$(cat <<EOF
{
  "Role": "arn:aws:iam::${MASTER_ACCOUNT_ID}:role/${REPLICATION_ROLE_NAME}",
  "Rules": [
    $REPLICATION_RULES
  ]
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

log_success "✓ Replication rules configured"

# Step 4: Verify replication configuration
log_info "Step 4: Verifying replication configuration..."

REPLICATION_STATUS=$(aws s3api get-bucket-replication \
    --bucket "$MASTER_CFN_BUCKET" \
    --region "$AWS_REGION" \
    --query 'ReplicationConfiguration.Rules[*].[ID,Status]' \
    --output table 2>/dev/null || echo "ERROR")

if [ "$REPLICATION_STATUS" != "ERROR" ]; then
    log_success "✓ Replication configuration verified"
    echo "$REPLICATION_STATUS"
else
    log_error "✗ Failed to verify replication configuration"
    exit 1
fi

echo ""
log_success "=========================================="
log_success "S3 Replication Setup Complete!"
log_success "=========================================="
echo ""
log_info "Configuration:"
echo "  • Replication Role: arn:aws:iam::${MASTER_ACCOUNT_ID}:role/${REPLICATION_ROLE_NAME}"
echo "  • Source Bucket: ${MASTER_CFN_BUCKET}"
echo "  • Replication Rules: $ACCOUNT_COUNT (one per child account)"
echo "  • Filter: lambdas/* (only Lambda packages)"
echo ""
log_info "How it works:"
echo "  1. Upload Lambda packages to s3://${MASTER_CFN_BUCKET}/lambdas/"
echo "  2. S3 automatically replicates to all child account buckets"
echo "  3. Replication typically completes within 15 minutes"
echo "  4. Child accounts can immediately use the Lambda packages"
echo ""
log_info "Next steps:"
echo "  • Lambda packages are already uploaded from step 5"
echo "  • Replication will start automatically"
echo "  • Wait 2-3 minutes for initial replication"
echo "  • Then proceed with Layer 2 deployment"
echo ""
