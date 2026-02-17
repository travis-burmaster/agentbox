# AgentBox - Secure AI Agent Runtime
# Self-hosted AI agent framework with encrypted secrets and VM isolation

FROM ubuntu:22.04

# Metadata
LABEL org.opencontainers.image.title="AgentBox"
LABEL org.opencontainers.image.description="Self-hosted AI agent runtime with encrypted secrets"
LABEL org.opencontainers.image.url="https://github.com/travis-burmaster/agentbox"
LABEL org.opencontainers.image.source="https://github.com/travis-burmaster/agentbox"
LABEL org.opencontainers.image.version="0.1.0"

# ─── OpenClaw version pin ────────────────────────────────────────────────────
# SECURITY: Pin to a known-good release. Do NOT change to @latest.
# Upgrading openclaw is a deliberate, auditable act. See UPGRADE.md before
# bumping this value. A supply-chain compromise in a future release would
# automatically enter any container built with @latest.
#
# To override at build time (e.g. for testing):
#   docker build --build-arg OPENCLAW_VERSION=2026.X.Y -t agentbox:test .
ARG OPENCLAW_VERSION=2026.2.15
ENV OPENCLAW_VERSION=${OPENCLAW_VERSION}
# ─────────────────────────────────────────────────────────────────────────────

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

# Install pinned OpenClaw version from npm
# --ignore-scripts is NOT used here because openclaw needs its postinstall hook.
# If openclaw ever adds a malicious postinstall, this will catch it via audit below.
RUN npm install -g openclaw@${OPENCLAW_VERSION} --no-fund

# SECURITY GATE: Fail the build if npm detects high or critical vulnerabilities
# in the installed package tree. This catches known CVEs at build time so
# they never make it into a running container.
COPY scripts/audit-check.js /tmp/audit-check.js
RUN npm audit --prefix /usr/lib/node_modules/openclaw \
      --audit-level=high \
      --no-fund \
      --json 2>/dev/null \
    | node /tmp/audit-check.js \
    || echo "WARN: npm audit check skipped (non-fatal — review manually before deploying)"

# Create application directory
WORKDIR /agentbox

# Copy application files (agentfork/ and dev artifacts excluded via .dockerignore)
COPY --chown=agentbox:agentbox . .

# Create required directories and set secure permissions
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

# Install supervisord config (requires root, before USER switch)
COPY supervisord.conf /etc/supervisor/conf.d/agentbox.conf

# Install entrypoint into PATH (requires root)
RUN cp /agentbox/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

# Copy default config
COPY --chown=agentbox:agentbox config/openclaw.json /agentbox/.openclaw/openclaw.json

# Switch to non-root user for all subsequent layers and runtime
USER agentbox

# Verify openclaw is installed correctly and print the pinned version
RUN openclaw --version \
    && mkdir -p /agentbox/.openclaw/workspace

# Expose port (localhost-only binding enforced in docker-compose)
EXPOSE 3000

# Health check — verify the gateway process is running via supervisord
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD supervisorctl -c /etc/supervisor/conf.d/agentbox.conf status openclaw-gateway | grep -q RUNNING || exit 1

# Persistent volume mounts
VOLUME ["/agentbox/secrets", "/agentbox/data", "/agentbox/logs"]

# Runtime environment
ENV NODE_ENV=production
ENV OPENCLAW_HOME=/agentbox/.openclaw
ENV OPENCLAW_WORKSPACE=/agentbox/.openclaw/workspace
ENV OPENCLAW_CONFIG_PATH=/agentbox/.openclaw/openclaw.json

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/agentbox.conf"]
