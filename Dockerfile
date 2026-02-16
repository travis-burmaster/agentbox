# AgentBox - Secure AI Agent Runtime
# Self-hosted AI agent framework with encrypted secrets and VM isolation

FROM ubuntu:22.04

# Metadata
LABEL org.opencontainers.image.title="AgentBox"
LABEL org.opencontainers.image.description="Self-hosted AI agent runtime with encrypted secrets"
LABEL org.opencontainers.image.url="https://github.com/travis-burmaster/agentbox"
LABEL org.opencontainers.image.source="https://github.com/travis-burmaster/agentbox"
LABEL org.opencontainers.image.version="0.1.0"

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Security: Run as non-root user
RUN useradd -m -s /bin/bash -u 1000 agentbox

# Install system dependencies (excluding Node.js - installed from NodeSource below)
RUN apt-get update && apt-get install -y \
    # Core utilities
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    # Build tools
    build-essential \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    # Security tools
    age \
    ufw \
    fail2ban \
    auditd \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22.x from NodeSource (required by OpenClaw)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install pnpm (required for OpenClaw build)
RUN npm install -g pnpm@latest

# Create application directory
WORKDIR /agentbox

# Copy agentfork source code (the core framework)
COPY --chown=agentbox:agentbox agentfork/ /agentbox/agentfork/

# Build and install agentbox from source
RUN cd /agentbox/agentfork \
    && npm install \
    && npm run build \
    && npm link

# Copy application files
COPY --chown=agentbox:agentbox . .

# Create required directories
RUN mkdir -p \
    /agentbox/secrets \
    /agentbox/data \
    /agentbox/logs \
    /agentbox/.agentbox/workspace \
    && chown -R agentbox:agentbox /agentbox

# Install Python dependencies (if any)
RUN if [ -f requirements.txt ]; then \
    pip3 install --no-cache-dir -r requirements.txt; \
    fi

# Security: Set proper permissions
RUN chmod 700 /agentbox/secrets \
    && chmod +x /agentbox/scripts/*.sh

# Switch to non-root user
USER agentbox

# Initialize AgentBox workspace
RUN openclaw init || true

# Expose port (only localhost binding recommended)
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Volume mounts for persistence
VOLUME ["/agentbox/secrets", "/agentbox/data", "/agentbox/logs"]

# Environment variables (override at runtime)
ENV NODE_ENV=production
ENV AGENTBOX_HOME=/agentbox
ENV AGENTBOX_WORKSPACE=/agentbox/.agentbox/workspace

# Entrypoint script
COPY --chown=agentbox:agentbox docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["openclaw", "gateway", "start"]
