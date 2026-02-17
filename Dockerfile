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

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Core utilities
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    # Build tools (needed for native npm modules)
    build-essential \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    # Process supervisor (container-native service management)
    supervisor \
    # Security tools
    age \
    ufw \
    fail2ban \
    auditd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22.x from NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install OpenClaw from npm (official published package)
# Pin to a specific version for reproducibility; update as new versions release
RUN npm install -g openclaw@latest

# Create application directory
WORKDIR /agentbox

# Copy application files (excludes agentfork/ and other dev artifacts via .dockerignore)
COPY --chown=agentbox:agentbox . .

# Create required directories and set permissions
RUN mkdir -p \
    /agentbox/secrets \
    /agentbox/data \
    /agentbox/logs \
    /agentbox/.openclaw/workspace \
    && chown -R agentbox:agentbox /agentbox \
    && chmod 700 /agentbox/secrets \
    && if ls /agentbox/scripts/*.sh >/dev/null 2>&1; then chmod +x /agentbox/scripts/*.sh; fi

# Install Python dependencies (if present)
RUN if [ -f requirements.txt ]; then \
    pip3 install --no-cache-dir -r requirements.txt; \
    fi

# Copy supervisord config (must run as root for /etc/supervisor)
COPY supervisord.conf /etc/supervisor/conf.d/agentbox.conf

# Install entrypoint script into PATH (must happen before USER switch)
RUN cp /agentbox/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

# Copy default config if not already present via volume
COPY --chown=agentbox:agentbox config/openclaw.json /agentbox/.openclaw/openclaw.json

# Switch to non-root user
USER agentbox

# Verify openclaw is installed and create workspace dirs
RUN openclaw --version \
    && mkdir -p /agentbox/.openclaw/workspace

# Expose port (only localhost binding recommended in production)
EXPOSE 3000

# Health check — verify the gateway process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD supervisorctl -c /etc/supervisor/conf.d/agentbox.conf status openclaw-gateway | grep -q RUNNING || exit 1

# Persistent volume mounts
VOLUME ["/agentbox/secrets", "/agentbox/data", "/agentbox/logs"]

# Runtime environment
ENV NODE_ENV=production
ENV OPENCLAW_HOME=/agentbox/.openclaw
ENV OPENCLAW_WORKSPACE=/agentbox/.openclaw/workspace
ENV OPENCLAW_CONFIG_PATH=/agentbox/.openclaw/openclaw.json

# Entrypoint + default command
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# supervisord manages openclaw-gateway; use `supervisorctl restart openclaw-gateway` to reload
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/agentbox.conf"]
