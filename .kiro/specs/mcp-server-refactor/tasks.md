# Implementation Plan: MCP Server Refactoring

## Overview
This plan refactors the MCP server deployment from CloudFormation-managed CodeBuild with inline code to a local Docker build approach with modular source files, following the same pattern as the coveo-agent deployment.

---

## Tasks

- [x] 1. Extract source files from CloudFormation template




  - Extract inline code from BuildSpec in `coveo-mcp-server/mcp-server-template.yaml` to separate files
  - Create `coveo-mcp-server/requirements.txt` with exact dependencies from BuildSpec
  - Create `coveo-mcp-server/coveo_api.py` with exact business logic from BuildSpec
  - Create `coveo-mcp-server/mcp_server.py` with exact MCP tool definitions from BuildSpec
  - Create `coveo-mcp-server/Dockerfile` with exact container configuration from BuildSpec
  - Preserve all business logic, SSM parameter paths, and error handling without modification
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [x] 2. Simplify CloudFormation template






  - [x] 2.1 Remove CodeBuild resources from template


    - Remove `CodeBuildRole` IAM role
    - Remove `MCPServerImageBuildProject` CodeBuild project
    - Remove `CustomResourceRole` IAM role
    - Remove `CodeBuildTriggerFunction` Lambda function
    - Remove `TriggerCodeBuild` custom resource
    - _Requirements: 2.2, 2.3, 7.1, 7.2, 7.3_
  
  - [x] 2.2 Add ImageUri parameter and update Runtime resource


    - Add `ImageUri` parameter to accept ECR image URI
    - Update `MCPServerRuntime` to use `!Ref ImageUri` instead of ECR repository output
    - Remove dependency on `TriggerCodeBuild` from `MCPServerRuntime`
    - Keep ECR repository, AgentExecutionRole, and SSM parameters unchanged
    - _Requirements: 7.4, 7.5, 7.6, 7.7, 7.8_


- [x] 3. Update deploy-mcp.sh script for local Docker build




  - [x] 3.1 Add Docker build section


    - Add Docker availability check before build
    - Navigate to `coveo-mcp-server/` directory
    - Build Docker image locally using `docker buildx build --platform linux/arm64`
    - Tag image with timestamp (YYYYMMDD-HHMMSS) and `latest`
    - Handle build failures with clear error messages
    - _Requirements: 2.1, 2.3, 2.4, 2.5, 2.7, 4.2, 4.5_
  
  - [x] 3.2 Add ECR authentication and push section


    - Authenticate to ECR using `aws ecr get-login-password`
    - Push Docker image to ECR with both timestamp and latest tags
    - Handle push failures with clear error messages
    - _Requirements: 2.4, 2.6, 4.2, 4.6_
  
  - [x] 3.3 Update CloudFormation deployment section


    - Remove S3 template upload logic
    - Use `--template-body file://` instead of `--template-url`
    - Add `ImageUri` parameter with ECR image URI
    - Pass Cognito parameters as before
    - Update both create-stack and update-stack commands
    - _Requirements: 2.5, 4.2, 4.3, 4.4_
  
  - [x] 3.4 Maintain backward compatibility


    - Keep same script name and location (`scripts/deploy-mcp.sh`)
    - Preserve existing environment variables (STACK_PREFIX, AWS_REGION)
    - Maintain same deployment flags and parameters
    - Keep orphaned resource cleanup logic
    - Keep SSM parameter writing logic
    - _Requirements: 4.1, 4.3, 4.4_

- [x] 4. Update destroy.sh script for new architecture





  - Remove CodeBuild project cleanup (no longer created)
  - Remove CodeBuild-related Lambda function cleanup
  - Remove CodeBuild-related IAM role cleanup
  - Keep ECR repository cleanup (images preserved for faster rebuilds)
  - Keep AgentCore Runtime cleanup
  - Keep SSM parameter cleanup
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [x] 5. Verify integration with complete workshop deployment






  - Ensure `deploy-complete-workshop.sh` calls `deploy-mcp.sh` unchanged
  - Verify deployment order: main-infra → mcp → agent → ui
  - Confirm no changes needed to other deployment scripts
  - Test complete workshop deployment end-to-end
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ]* 6. Test and validate deployment
  - [ ]* 6.1 Test local Docker build
    - Build image locally and verify it completes successfully
    - Check image size is reasonable (~200MB)
    - Verify ARM64 platform
    - _Requirements: 2.3, 2.4_
  
  - [ ]* 6.2 Test ECR push
    - Push image to ECR and verify upload completes
    - Check both timestamp and latest tags exist
    - _Requirements: 2.4, 2.6_
  
  - [ ]* 6.3 Test CloudFormation deployment
    - Deploy stack and verify it creates successfully
    - Check AgentCore Runtime becomes ACTIVE
    - Verify no CodeBuild resources created
    - _Requirements: 2.5, 7.1, 7.2, 7.3, 7.8_
  
  - [ ]* 6.4 Test MCP tool functionality
    - Invoke MCP Runtime and verify it responds
    - Test search_coveo tool with sample query
    - Test passage_retrieval tool with sample query
    - Test answer_question tool with sample query
    - Verify SSM parameters are read correctly
    - _Requirements: 3.2, 3.3, 3.4, 3.5_
  
  - [ ]* 6.5 Test Agent Runtime integration
    - Deploy Agent Runtime pointing to MCP Runtime
    - Invoke Agent with test query
    - Verify Agent can call MCP tools successfully
    - Check end-to-end flow works
    - _Requirements: 5.1, 5.2_
  
  - [ ]* 6.6 Test complete workshop deployment
    - Run `deploy-complete-workshop.sh`
    - Verify all components deploy successfully
    - Test UI → API Gateway → Lambda → Agent → MCP → Coveo flow
    - _Requirements: 5.1, 5.2, 5.3_
  
  - [ ]* 6.7 Test cleanup script
    - Run `destroy.sh` and verify all resources deleted
    - Check no orphaned CodeBuild resources
    - Verify ECR images preserved
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

---

## Notes

- **Business Logic Preservation**: All code in `coveo_api.py` and `mcp_server.py` must be extracted exactly as-is from the BuildSpec without modifications
- **SSM Parameters**: Parameter paths must remain `/{STACK_PREFIX}/coveo/*` for compatibility
- **MCP Tool Definitions**: Tool signatures and response formats must remain unchanged for Agent Runtime compatibility
- **Deployment Pattern**: Follow the same local Docker build pattern used by `coveo-agent` for consistency
- **Testing**: Optional test tasks (marked with *) focus on validation but are not required for core functionality
- **Backward Compatibility**: The `deploy-mcp.sh` script interface must remain unchanged for integration with `deploy-complete-workshop.sh`

---

## Success Criteria

- [ ] Source files extracted and organized in `coveo-mcp-server/` directory
- [ ] CloudFormation template simplified (no CodeBuild resources)
- [ ] `deploy-mcp.sh` builds Docker image locally and pushes to ECR
- [ ] MCP Runtime deploys successfully with new architecture
- [ ] MCP tools respond correctly to invocations
- [ ] Agent Runtime can call MCP tools successfully
- [ ] Complete workshop deployment works end-to-end
- [ ] Cleanup script removes all resources properly
