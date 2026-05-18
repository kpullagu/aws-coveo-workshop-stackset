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

# Env: model, region, Hosted MCP configuration is loaded from SSM at runtime
ENV AWS_REGION=us-east-1
ENV BEDROCK_MODEL_ID=us.amazon.nova-lite-v1:0

EXPOSE 8080

# Lightweight healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/ping || exit 1

USER appuser
# Use OpenTelemetry auto-instrumentation for observability
CMD ["opentelemetry-instrument", "python", "app.py"]
