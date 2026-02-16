# AgentBox Telemetry Dashboard
# Streamlit-based observability dashboard for OpenClaw sessions

FROM python:3.11-slim

LABEL org.opencontainers.image.title="AgentBox Telemetry"
LABEL org.opencontainers.image.description="Real-time observability dashboard for AgentBox/OpenClaw"
LABEL org.opencontainers.image.url="https://github.com/travis-burmaster/agentbox"

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY dashboard.py session_parser.py ./

# Create log directory
RUN mkdir -p /tmp/openclaw

# Expose Streamlit default port
EXPOSE 8501

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8501/_stcore/health || exit 1

# Run Streamlit dashboard
CMD ["streamlit", "run", "dashboard.py", "--server.port=8501", "--server.address=0.0.0.0", "--server.headless=true"]
