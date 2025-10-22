#!/bin/bash

###############################################################################
# Update Cognito Callback URLs
#
# This script updates the Cognito User Pool Client with the S3 website URL
# after the infrastructure is deployed. This is needed because of the circular
# dependency between AuthStack and CoreStack.
#
# Usage:
#   ./scripts/update-cognito-callbacks.sh --stack-prefix workshop --region us-east-1
###############################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
STACK_PREFIX="workshop"
AWS_REGION="us-east-1"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stack-prefix)
            STACK_PREFIX="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

echo -e "${YELLOW}Updating Cognito callback URLs...${NC}"

# Get CloudFormation outputs
MASTER_STACK="${STACK_PREFIX}-master"

USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name "$MASTER_STACK" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text)

CLIENT_ID=$(aws cloudformation describe-stacks \
    --stack-name "$MASTER_STACK" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" \
    --output text)

# Get App Runner URL from UI stack
APP_RUNNER_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-ui-apprunner" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AppRunnerServiceUrl'].OutputValue" \
    --output text 2>/dev/null || echo "")

# Fallback: Try to get S3 Website URL if App Runner not found
S3_WEBSITE_URL=$(aws cloudformation describe-stacks \
    --stack-name "$MASTER_STACK" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='S3WebsiteURL'].OutputValue" \
    --output text 2>/dev/null || echo "")

echo "User Pool ID: $USER_POOL_ID"
echo "Client ID: $CLIENT_ID"
echo "App Runner URL: $APP_RUNNER_URL"
echo "S3 Website URL: $S3_WEBSITE_URL"

# Build callback URLs array (only include non-empty URLs)
CALLBACK_URLS=()
LOGOUT_URLS=()

# Prefer App Runner URL
if [ -n "$APP_RUNNER_URL" ] && [ "$APP_RUNNER_URL" != "None" ]; then
    CALLBACK_URLS+=("$APP_RUNNER_URL")
    LOGOUT_URLS+=("$APP_RUNNER_URL")
elif [ -n "$S3_WEBSITE_URL" ] && [ "$S3_WEBSITE_URL" != "None" ]; then
    CALLBACK_URLS+=("$S3_WEBSITE_URL")
    LOGOUT_URLS+=("$S3_WEBSITE_URL")
fi

# Always include localhost for development
CALLBACK_URLS+=("http://localhost:3000")
LOGOUT_URLS+=("http://localhost:3000")

# Convert arrays to space-separated strings
CALLBACK_URLS_STR="${CALLBACK_URLS[@]}"
LOGOUT_URLS_STR="${LOGOUT_URLS[@]}"

echo "Callback URLs to set: $CALLBACK_URLS_STR"
echo "Logout URLs to set: $LOGOUT_URLS_STR"

# Update the User Pool Client with complete OAuth configuration
# IMPORTANT: Must specify ALL parameters to avoid resetting OAuth settings to defaults
echo "Updating Cognito User Pool Client with OAuth configuration..."
aws cognito-idp update-user-pool-client \
    --user-pool-id "$USER_POOL_ID" \
    --client-id "$CLIENT_ID" \
    --callback-urls $CALLBACK_URLS_STR \
    --logout-urls $LOGOUT_URLS_STR \
    --allowed-o-auth-flows "code" \
    --allowed-o-auth-scopes "email" "openid" "profile" \
    --allowed-o-auth-flows-user-pool-client \
    --supported-identity-providers "COGNITO" \
    --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" "ALLOW_USER_SRP_AUTH" \
    --region "$AWS_REGION"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Cognito callback URLs and OAuth configuration updated${NC}"
    echo "  - OAuth flows enabled: code"
    echo "  - OAuth scopes: email, openid, profile"
    echo "  - AllowedOAuthFlowsUserPoolClient: true"
else
    echo -e "${YELLOW}⚠️  Warning: Cognito update may have failed${NC}"
    echo "  You may need to manually enable OAuth in the Cognito console"
    exit 1
fi
