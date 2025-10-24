# =============================================================================
# Configure Cognito (Final Step)
# =============================================================================

# Set defaults if not already set (for standalone execution)
STACK_PREFIX="${STACK_PREFIX:-workshop}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors for output (if not already set)
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"
BLUE="${BLUE:-\033[0;34m}"
NC="${NC:-\033[0m}"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Configuring Cognito Authentication${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}ℹ️  Setting up test user and callback URLs...${NC}"
echo ""

# Debug: Show what we're looking for
echo -e "${BLUE}ℹ️  Looking for stack: ${STACK_PREFIX}-master in region: ${AWS_REGION}${NC}"

# Get Cognito info from master stack
COGNITO_USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

COGNITO_CLIENT_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

COGNITO_HOSTED_UI_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-master" \
    --query "Stacks[0].Outputs[?OutputKey=='CognitoHostedUIUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

APP_RUNNER_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-ui-apprunner" \
    --query "Stacks[0].Outputs[?OutputKey=='AppRunnerServiceUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

# Debug output
echo -e "${BLUE}ℹ️  Found User Pool ID: ${COGNITO_USER_POOL_ID:-NOT FOUND}${NC}"
echo -e "${BLUE}ℹ️  Found Client ID: ${COGNITO_CLIENT_ID:-NOT FOUND}${NC}"

if [ -z "$COGNITO_USER_POOL_ID" ] || [ -z "$COGNITO_CLIENT_ID" ]; then
    echo -e "${RED}❌ Failed to retrieve Cognito configuration${NC}"
    echo -e "${YELLOW}⚠️  Make sure the CloudFormation stack '${STACK_PREFIX}-master' exists and has completed successfully${NC}"
    echo -e "${YELLOW}⚠️  Check the stack outputs in the AWS Console${NC}"
    exit 1
fi

# Create test user (read from .env or use defaults)
TEST_USER_EMAIL="${TEST_USER_EMAIL:-awsworkshop@coveo.com}"
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-WelcomeToCoveo1}"

echo -e "${BLUE}ℹ️  Creating test user: $TEST_USER_EMAIL (from .env or default)${NC}"
aws cognito-idp admin-create-user \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$TEST_USER_EMAIL" \
    --user-attributes \
        Name=email,Value=$TEST_USER_EMAIL \
        Name=email_verified,Value=true \
    --message-action SUPPRESS \
    --region "$AWS_REGION" 2>/dev/null || echo -e "${YELLOW}⚠️  User may already exist${NC}"

# Set permanent password
echo -e "${BLUE}ℹ️  Setting permanent password: $TEST_USER_PASSWORD${NC}"
aws cognito-idp admin-set-user-password \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$TEST_USER_EMAIL" \
    --password "$TEST_USER_PASSWORD" \
    --permanent \
    --region "$AWS_REGION" 2>/dev/null

echo -e "${GREEN}✅ Test user configured successfully${NC}"

# Update Cognito callback URLs
if [ -n "$APP_RUNNER_URL" ] && [ "$APP_RUNNER_URL" != "Not available" ]; then
    echo -e "${BLUE}ℹ️  Updating Cognito callback URLs with App Runner domain...${NC}"
    
    # Update Cognito App Client with complete OAuth configuration
    aws cognito-idp update-user-pool-client \
        --user-pool-id "$COGNITO_USER_POOL_ID" \
        --client-id "$COGNITO_CLIENT_ID" \
        --callback-urls "$APP_RUNNER_URL" "http://localhost:3000" \
        --logout-urls "$APP_RUNNER_URL" "http://localhost:3000" \
        --allowed-o-auth-flows "code" \
        --allowed-o-auth-scopes "email" "openid" "profile" \
        --allowed-o-auth-flows-user-pool-client \
        --supported-identity-providers "COGNITO" \
        --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" "ALLOW_USER_SRP_AUTH" \
        --region "$AWS_REGION" >/dev/null 2>&1
    
    echo -e "${GREEN}✅ Callback URLs updated successfully${NC}"
fi

echo ""