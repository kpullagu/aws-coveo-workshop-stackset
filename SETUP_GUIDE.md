# AWS Coveo Workshop - Setup Guide

> This guide reflects the refreshed workshop target state: Coveo Hosted MCP for Lab 3 and Amazon ECS Express Mode for the UI.

## 🚀 Quick Start

### Prerequisites
- AWS Organizations with at least one OU
- AWS CLI configured with admin access to master account
- Docker installed (for building images)
- jq installed (for JSON processing)

---

## 📋 Step 1: Clone Repository

```bash
git clone <repository-url>
cd aws-coveo-workshop
```

---

## 🔧 Step 2: Configure Environment

### Create Configuration File

```bash
# Copy the example configuration
cp .env.stacksets.example .env.stacksets
```

### Edit `.env.stacksets` with Your Values

```bash
# Open in your editor
nano .env.stacksets
# or
code .env.stacksets
```

### Required Configuration

Update these values in `.env.stacksets`:

```bash
# ============================================================================
# AWS Organizations Configuration (REQUIRED)
# ============================================================================

# Your AWS Organizations OU ID
# Find it in: AWS Console → Organizations → Organizational Units
OU_ID=ou-xxxx-xxxxxxxx

# Your master/management account ID
# Find it in: AWS Console → Account Settings
MASTER_ACCOUNT_ID=123456789012

# AWS Region for deployment
AWS_REGION=us-east-1

# Stack prefix (used for all resource names)
STACK_PREFIX=workshop

# ============================================================================
# Coveo Configuration (REQUIRED)
# ============================================================================

# Get these from: https://platform.cloud.coveo.com

# Your Coveo Organization ID
COVEO_ORG_ID=your-org-id-here

# Coveo Search API Key (with search permissions)
COVEO_SEARCH_API_KEY=xx00000000-0000-0000-0000-000000000000

# Coveo Answer Configuration ID
COVEO_ANSWER_CONFIG_ID=00000000-0000-0000-0000-000000000000

# Hosted MCP configuration
COVEO_HOSTED_MCP_CONFIG_NAME=Workshop-MCP-server
COVEO_HOSTED_MCP_ENDPOINT=https://platform.cloud.coveo.com/api/preview/organizations/awsworkshopthsskpki/mcp/server/f9552f36-24e1-47b6-8c55-d6fe87553c61
COVEO_HOSTED_MCP_AUTH_MODE=anonymous_api_key
COVEO_HOSTED_MCP_API_KEY=xx00000000-0000-0000-0000-000000000000
COVEO_HOSTED_MCP_SEARCH_HUB=MCP_Workshop-MCP-server

# Workshop query pipeline
COVEO_SEARCH_PIPELINE=aws-workshop-pipeline

# ============================================================================
# Test User Configuration (OPTIONAL)
# ============================================================================

# Cognito test user credentials
TEST_USER_EMAIL=workshop-user@example.com
TEST_USER_PASSWORD=ChangeMe123!
```

---

## ✅ Step 3: Verify Configuration

```bash
# Check that .env.stacksets exists and is not committed
git status | grep .env.stacksets
# Should show: nothing (file is ignored)

# Verify configuration loads correctly
bash scripts/stacksets/config.sh
# Should not show any errors
```

---

## 🚀 Step 4: Deploy

### One-Command Deployment

```bash
bash scripts/stacksets/deploy-all-stacksets.sh
```

This will:
1. ✅ Setup master account ECR repositories
2. ✅ Build and push Docker images (Agent, UI)
3. ✅ Create shared Lambda layer
4. ✅ Package Lambda functions
5. ✅ Deploy Layer 1 (Prerequisites) to all accounts
6. ✅ Setup S3 cross-account replication
7. ✅ Deploy Layer 2 (Core Infrastructure)
8. ✅ Deploy Layer 3 (AI Services - Bedrock Agent, AgentCore Runtime, Hosted MCP config wiring)
9. ✅ Deploy Layer 4 (UI - ECS Express Mode)
10. ✅ Configure Cognito and collect deployment info

**Estimated Time**: 45-60 minutes

---

## 🧹 Cleanup

### Remove All Resources

```bash
bash scripts/stacksets/destroy-all-stacksets-v2.sh
```

This will:
- Delete all StackSets in reverse order
- Empty S3 buckets
- Delete ECR images
- Remove CloudWatch log groups
- Clean up all workshop resources

---

## 🔒 Security Best Practices

### ✅ What's Protected

Your `.gitignore` ensures these files are NEVER committed:
- `.env` - Frontend credentials
- `.env.stacksets` - Deployment credentials
- `*.pem`, `*.key` - Private keys
- `.aws/credentials` - AWS credentials

### ⚠️ Important Notes

1. **Never commit `.env.stacksets`**
   - Contains your AWS account IDs
   - Contains Coveo API keys
   - Contains test user passwords

2. **Use `.env.stacksets.example` as template**
   - Safe to commit (contains only placeholders)
   - Share with team members
   - Update when adding new configuration

3. **Rotate credentials regularly**
   - Change `TEST_USER_PASSWORD` after workshop
   - Rotate Coveo API keys periodically
   - Review AWS IAM permissions

---

## 📁 Configuration Files

| File | Purpose | Committed? |
|------|---------|------------|
| `.env.stacksets.example` | Template with placeholders | ✅ Yes |
| `.env.stacksets` | Your actual configuration | ❌ No (gitignored) |
| `scripts/stacksets/config.sh` | Loads from `.env.stacksets` | ✅ Yes |
| `.env` | Frontend configuration | ❌ No (gitignored) |
| `.env.example` | Frontend template | ✅ Yes |

---

## 🔍 Troubleshooting

### Error: ".env.stacksets file not found"

```bash
# Solution: Create the file from template
cp .env.stacksets.example .env.stacksets
# Then edit with your values
```

### Error: "Missing required configuration"

```bash
# Solution: Check that all required variables are set
cat .env.stacksets | grep -E "OU_ID|MASTER_ACCOUNT_ID|COVEO"
```

### Error: "Cannot assume role"

```bash
# Solution: Verify OrganizationAccountAccessRole exists in child accounts
aws iam get-role \
  --role-name OrganizationAccountAccessRole \
  --profile child-account
```

---

## 📚 Additional Resources

- [AWS Organizations Documentation](https://docs.aws.amazon.com/organizations/)
- [AWS StackSets Documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- [Coveo Platform Documentation](https://docs.coveo.com/)
- [Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html)

---

## 🆘 Support

If you encounter issues:

1. Check the logs in CloudWatch
2. Review the deployment output
3. Verify your `.env.stacksets` configuration
4. Check AWS Organizations permissions

---

## ✨ What Gets Deployed

### Master Account
- ECR repositories (Agent, UI images)
- S3 bucket (Lambda packages, CloudFormation templates)
- Lambda Layer (shared dependencies)

### Child Accounts (via StackSets)
- **Layer 1**: S3 buckets, IAM roles
- **Layer 2**: Lambda functions, API Gateway, Cognito
- **Layer 3**: Bedrock Agent, AgentCore Runtime, AgentCore Memory
- **Layer 4**: ECS Express Mode service (UI)

### Observability
- X-Ray tracing with session correlation
- CloudWatch Logs with structured logging
- Bedrock model invocation logging
- X-Ray span ingestion to CloudWatch

---

**Ready to deploy?** Follow the steps above and you'll have a fully functional multi-account Coveo workshop environment!
