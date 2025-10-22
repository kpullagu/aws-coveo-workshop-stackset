# Requirements Document: MCP Server Refactoring

## Introduction

Refactor the MCP (Model Context Protocol) server deployment from a single CloudFormation template with inline code to a modular structure with separate source files and local Docker build process. This change improves maintainability, enables local testing, and removes the CodeBuild dependency while preserving all business logic.

## Glossary

- **MCP Server**: Model Context Protocol server that provides Coveo API tools to the Agent Runtime
- **Inline Code**: Code embedded directly in CloudFormation template BuildSpec
- **Local Build**: Docker image built on developer's machine instead of AWS CodeBuild
- **ECR**: Amazon Elastic Container Registry for storing Docker images
- **Agent Runtime**: The orchestrator that calls MCP tools
- **Source Files**: Python files (coveo_api.py, mcp_server.py), requirements.txt, and Dockerfile
- **Business Logic**: Core functionality in coveo_api.py and mcp_server.py that must remain unchanged

## Requirements

### Requirement 1: Extract Inline Code to Separate Files

**User Story:** As a developer, I want the MCP server code in separate files so that I can edit, test, and version control them easily.

#### Acceptance Criteria

1. WHEN the MCP server is deployed, THE System SHALL use source files from `coveo-mcp-server/src/` directory
2. THE System SHALL create the following files with exact code from the template:
   - `coveo-mcp-server/src/requirements.txt`
   - `coveo-mcp-server/src/coveo_api.py`
   - `coveo-mcp-server/src/mcp_server.py`
   - `coveo-mcp-server/Dockerfile`
3. THE System SHALL preserve all business logic without modification
4. WHERE SSM parameter access is required, THE System SHALL maintain the same parameter paths (`/workshop/coveo/*`)

### Requirement 2: Replace CodeBuild with Local Docker Build

**User Story:** As a developer, I want to build the Docker image locally so that I can test changes faster and reduce AWS service dependencies.

#### Acceptance Criteria

1. THE System SHALL remove all CodeBuild resources from the CloudFormation template
2. THE System SHALL remove the CodeBuildTriggerFunction Lambda from the template
3. WHEN `deploy-mcp.sh` is executed, THE System SHALL build the Docker image locally using the Dockerfile
4. WHEN the Docker build completes, THE System SHALL push the image to ECR
5. WHEN the image is pushed to ECR, THE System SHALL deploy the CloudFormation template with the new image
6. THE System SHALL authenticate to ECR before pushing the Docker image
7. THE System SHALL tag the Docker image with a timestamp or version identifier

### Requirement 3: Preserve Business Logic

**User Story:** As a developer, I want the core MCP functionality to remain unchanged so that existing integrations continue to work.

#### Acceptance Criteria

1. THE System SHALL extract code from the template BuildSpec without modifying the business logic
2. THE System SHALL maintain the same Coveo API endpoints and request formats
3. THE System SHALL maintain the same MCP tool definitions (search_coveo, retrieve_passages, generate_answer)
4. THE System SHALL maintain the same SSM parameter reading logic
5. THE System SHALL maintain the same error handling and logging behavior
6. WHERE environment variables are used, THE System SHALL use the same variable names

### Requirement 4: Update deploy-mcp.sh Script

**User Story:** As a developer, I want to deploy the MCP server using the same script so that the deployment process remains consistent.

#### Acceptance Criteria

1. THE System SHALL use `scripts/deploy-mcp.sh` for MCP server deployment
2. WHEN `deploy-mcp.sh` is executed, THE System SHALL perform the following steps in order:
   - Check for orphaned resources
   - Retrieve Cognito configuration
   - Build Docker image locally
   - Push image to ECR
   - Deploy CloudFormation template
   - Save runtime ARN to SSM
3. THE System SHALL NOT create new deployment scripts
4. THE System SHALL maintain backward compatibility with existing deployment flags and parameters
5. WHEN the Docker build fails, THE System SHALL exit with an error message
6. WHEN the ECR push fails, THE System SHALL exit with an error message

### Requirement 5: Maintain Integration with Complete Workshop Deployment

**User Story:** As a developer, I want the complete workshop deployment to include the MCP server so that all components are deployed together.

#### Acceptance Criteria

1. WHEN `deploy-complete-workshop.sh` is executed, THE System SHALL deploy the MCP server as part of the workflow
2. THE System SHALL deploy the MCP server after main infrastructure and before Agent Runtime
3. THE System SHALL NOT modify the deployment order of other components
4. THE System SHALL NOT modify code unrelated to MCP server deployment

### Requirement 6: Update Cleanup Script

**User Story:** As a developer, I want the destroy script to clean up MCP resources so that I can remove all workshop components cleanly.

#### Acceptance Criteria

1. WHEN `destroy.sh` is executed, THE System SHALL delete the MCP CloudFormation stack
2. THE System SHALL delete the ECR repository and all images
3. THE System SHALL delete SSM parameters created by the MCP deployment
4. THE System SHALL delete the AgentCore Runtime created by the MCP stack
5. THE System SHALL handle cases where resources do not exist without failing

### Requirement 7: Simplified CloudFormation Template

**User Story:** As a developer, I want a simpler CloudFormation template so that it's easier to understand and maintain.

#### Acceptance Criteria

1. THE System SHALL remove the CodeBuild project resource from the template
2. THE System SHALL remove the CodeBuild IAM role from the template
3. THE System SHALL remove the Lambda custom resource for triggering builds from the template
4. THE System SHALL keep the ECR repository resource in the template
5. THE System SHALL keep the AgentCore Runtime resource in the template
6. THE System SHALL keep the IAM roles required for AgentCore Runtime
7. THE System SHALL accept an ECR image URI as a parameter
8. WHEN the stack is created, THE System SHALL use the provided ECR image URI for the AgentCore Runtime

## Non-Functional Requirements

### Performance
- Docker build time SHALL NOT exceed 5 minutes
- ECR push time SHALL NOT exceed 3 minutes
- Total deployment time SHALL NOT exceed 15 minutes

### Maintainability
- Source files SHALL be organized in a clear directory structure
- Code SHALL include comments explaining SSM parameter usage
- Dockerfile SHALL use multi-stage builds if beneficial for size optimization

### Compatibility
- Solution SHALL work on Windows (WSL), macOS, and Linux
- Solution SHALL support Docker Desktop and native Docker installations
- Solution SHALL maintain compatibility with existing Agent Runtime integration

## Constraints

1. Business logic in coveo_api.py and mcp_server.py MUST remain unchanged
2. SSM parameter paths MUST remain the same (`/workshop/coveo/*`)
3. MCP tool definitions MUST remain compatible with Agent Runtime
4. Deployment MUST use existing `deploy-mcp.sh` script
5. No new deployment scripts SHALL be created
6. Changes SHALL be limited to MCP-related code only
