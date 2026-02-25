# AgentBox Marketing — Production Container
# Optimized for Cloud Run scale-to-zero:
#   - Slim base image for fast pull
#   - Dependencies pre-cached
#   - Boot time target: <5 seconds (cold), <1s (warm)

FROM python:3.12-slim

WORKDIR /app

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Python deps first (Docker layer cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY agent/ ./agent/
COPY scripts/ ./scripts/

# Non-root user for security
RUN useradd -m -u 1000 agentbox && chown -R agentbox:agentbox /app
USER agentbox

# Health check endpoint (Cloud Run requires HTTP)
EXPOSE 8080

# Entry point: Kafka consumer loop
# Cloud Run will start this on each trigger/pull
CMD ["python", "-m", "agent.kafka_consumer"]
