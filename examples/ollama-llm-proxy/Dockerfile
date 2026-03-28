# AgentBox + LLM Proxy (Ollama Facade)
#
# Three services in one container (supervisord):
#   1. claude_proxy   :8319  — OAuth proxy to Anthropic API
#   2. ollama-facade  :11434 — Ollama-compatible frontend
#   3. openclaw-gateway :3000 — AI agent runtime
#
# Usage:
#   docker compose up -d   (from examples/ollama-llm-proxy/)

FROM ubuntu:22.04

ARG OPENCLAW_VERSION=2026.2.15
ENV OPENCLAW_VERSION=${OPENCLAW_VERSION}
ENV DEBIAN_FRONTEND=noninteractive

# ── Non-root user ──────────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash -d /agentbox -u 1000 agentbox

# ── System deps ────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git ca-certificates \
    build-essential \
    python3 python3-pip \
    supervisor \
    procps \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 ─────────────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── OpenClaw ───────────────────────────────────────────────────────────────
RUN npm install -g openclaw@${OPENCLAW_VERSION} --ignore-scripts \
    && openclaw --version

# ── LLM Proxy Python deps ──────────────────────────────────────────────────
RUN pip3 install --no-cache-dir \
    fastapi \
    "uvicorn[standard]" \
    openai \
    pyyaml \
    httpx \
    curl-cffi

# ── LLM Proxy source (cloned from GitHub at build time) ───────────────────
RUN git clone --depth 1 https://github.com/travis-burmaster/llm-proxy.git /app/llm-proxy

# ── App config ─────────────────────────────────────────────────────────────
COPY config/llm-proxy.yaml /app/llm-proxy/config.yaml
RUN chmod 644 /app/llm-proxy/config.yaml

# ── Directory layout ───────────────────────────────────────────────────────
RUN mkdir -p \
    /agentbox/.openclaw/workspace \
    /agentbox/data \
    /agentbox/logs \
    /tmp/openclaw \
    && chown -R agentbox:agentbox /agentbox /tmp/openclaw

# ── OpenClaw config ────────────────────────────────────────────────────────
COPY config/openclaw.json /agentbox/.openclaw/openclaw.json
RUN chown agentbox:agentbox /agentbox/.openclaw/openclaw.json

# ── Supervisor + entrypoint ────────────────────────────────────────────────
COPY supervisord.conf /etc/supervisor/conf.d/agentbox.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 3000 11434 8319

ENV HOME=/agentbox
ENV NODE_ENV=production
ENV OPENCLAW_CONFIG_PATH=/agentbox/.openclaw/openclaw.json

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=30s \
    CMD curl -sf http://localhost:8319/ && curl -sf http://localhost:11434/ && pgrep -f openclaw-gateway || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
