# =============================================================================
# Configure Cognito (Final Step)
# =============================================================================
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Configuring Cognito Authentication${NC}"
echo -e "${BLUE}==============================================================================${NC}"
print_status "Setting up test user and callback URLs..." "INFO"
echo ""

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

if [ -z "$COGNITO_USER_POOL_ID" ] || [ -z "$COGNITO_CLIENT_ID" ]; then
    print_status "Failed to retrieve Cognito configuration" "ERROR"
    exit 1
fi

# Create test user (read from .env or use defaults)
TEST_USER_EMAIL="${TEST_USER_EMAIL:-testuser@example.com}"
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-TempPassword123!}"

print_status "Creating test user: $TEST_USER_EMAIL (from .env or default)" "INFO"
aws cognito-idp admin-create-user \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$TEST_USER_EMAIL" \
    --user-attributes \
        Name=email,Value=$TEST_USER_EMAIL \
        Name=email_verified,Value=true \
    --message-action SUPPRESS \
    --region "$AWS_REGION" 2>/dev/null || print_status "User may already exist" "WARNING"

# Set permanent password
print_status "Setting permanent password: $TEST_USER_PASSWORD" "INFO"
aws cognito-idp admin-set-user-password \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$TEST_USER_EMAIL" \
    --password "$TEST_USER_PASSWORD" \
    --permanent \
    --region "$AWS_REGION" 2>/dev/null

print_status "Test user configured successfully" "SUCCESS"

# Update Cognito callback URLs
if [ -n "$APP_RUNNER_URL" ] && [ "$APP_RUNNER_URL" != "Not available" ]; then
    print_status "Updating Cognito callback URLs with App Runner domain..." "INFO"
    
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
    
    print_status "Callback URLs updated successfully" "SUCCESS"
fi

echo ""