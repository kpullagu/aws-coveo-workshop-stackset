# Dockerfile — Agent runtime container (ARM64-friendly)
FROM python:3.11-slim

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 10001 appuser
WORKDIR /app

# Copy code
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# Env: model, region, MCP runtime
ENV AWS_REGION=us-east-1
ENV BEDROCK_MODEL_ID=us.anthropic.claude-3-7-sonnet-20250219-v1:0
# One of these must be set at deploy time:
# ENV COVEO_MCP_RUNTIME_ARN=arn:aws:bedrock-agentcore:us-west-2:123456789:runtime/coveo-mcp-xyz
# ENV COVEO_MCP_URL=http://localhost:8000/mcp

EXPOSE 8080

# Lightweight healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/ping || exit 1

USER appuser
CMD ["python", "app.py"]
