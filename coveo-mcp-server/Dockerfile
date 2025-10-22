FROM public.ecr.aws/docker/library/python:3.11-slim

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Set AWS environment variables
# Note: Coveo credentials will be passed by AgentCore Runtime at startup
ENV AWS_REGION=us-east-1
ENV AWS_DEFAULT_REGION=us-east-1

# Create non-root user for security
RUN useradd -m -u 1000 bedrock_agentcore

# Copy application code
COPY . .

# Change ownership of app directory
RUN chown -R bedrock_agentcore:bedrock_agentcore /app

# Switch to non-root user
USER bedrock_agentcore

# Expose port
EXPOSE 8000

# Run the MCP server using module syntax (required for FastMCP)
CMD ["python", "-m", "mcp_server"]
