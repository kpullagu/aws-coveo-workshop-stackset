#!/bin/bash
#
# Update ECR repository policy to allow cross-account pulls
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=========================================="
log_info "Updating ECR Repository Policy"
log_info "=========================================="
echo ""

# Get child accounts
ACCOUNT_IDS=$(aws organizations list-accounts-for-parent \
    --parent-id "$OU_ID" \
    --query 'Accounts[?Status==`ACTIVE`].Id' \
    --output text)

# ECR repositories
REPOS=(
    "${STACK_PREFIX}-coveo-mcp-server-master"
    "${STACK_PREFIX}-ui-master"
    "${STACK_PREFIX}-coveo-agent-master"
)

log_info "Master Account: $MASTER_ACCOUNT_ID"
log_info "Child Accounts: $ACCOUNT_IDS"
log_info "Repositories: ${#REPOS[@]}"
echo ""

for REPO in "${REPOS[@]}"; do
    log_info "Updating policy for: $REPO"
    
    # Build principal list for all child accounts
    PRINCIPALS=""
    for ACCOUNT_ID in $ACCOUNT_IDS; do
        if [ -z "$PRINCIPALS" ]; then
            PRINCIPALS="\"arn:aws:iam::${ACCOUNT_ID}:root\""
        else
            PRINCIPALS="$PRINCIPALS, \"arn:aws:iam::${ACCOUNT_ID}:root\""
        fi
    done
    
    # Create policy
    POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCrossAccountPull",
      "Effect": "Allow",
      "Principal": {
        "AWS": [$PRINCIPALS]
      },
      "Action": [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability"
      ]
    },
    {
      "Sid": "AllowBedrockAgentCorePull",
      "Effect": "Allow",
      "Principal": {
        "Service": "bedrock-agentcore.amazonaws.com"
      },
      "Action": [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability"
      ]
    }
  ]
}
EOF
)
    
    # Apply policy
    echo "$POLICY" > /tmp/ecr-policy.json
    
    if aws ecr set-repository-policy \
        --repository-name "$REPO" \
        --policy-text file:///tmp/ecr-policy.json \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_success "  ✅ Policy updated"
    else
        log_warning "  ⚠️  Failed to update policy (repo may not exist)"
    fi
    
    rm /tmp/ecr-policy.json
done

echo ""
log_success "=========================================="
log_success "ECR Repository Policies Updated!"
log_success "=========================================="
echo ""
log_info "All child accounts can now pull from master ECR repositories"
echo ""
