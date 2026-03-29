# AgentBox + LLM Proxy + GitAgent Example (public, self-contained)
# Proxy files are vendored in proxy/ — no private repo dependency.
#
# Four processes (supervisord):
#   1. claude-proxy   (:8319)  — OAuth → Anthropic, no CLIProxyAPI needed
#   2. ollama-facade  (:11434) — Ollama-compatible frontend
#   3. openclaw-gateway (:3000) — AI agent runtime
#   4. backup-cron    (none)   — Periodic workspace/data backup

FROM ubuntu:22.04

ARG OPENCLAW_VERSION=2026.3.24
ENV OPENCLAW_VERSION=${OPENCLAW_VERSION}
ENV DEBIAN_FRONTEND=noninteractive

# ── Non-root user ──────────────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash -d /agentbox -u 1000 agentbox

# ── System deps ────────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git ca-certificates \
    build-essential \
    python3 python3-pip \
    supervisor \
    procps \
    zip unzip \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 22 (required by openclaw ≥2026.3.x) ───────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── OpenClaw ───────────────────────────────────────────────────────────────────
RUN npm install -g openclaw@${OPENCLAW_VERSION} \
    && openclaw --version

# ── Python deps for claude_proxy.py + proxy_core.py + ollama-facade ───────────
RUN pip3 install --no-cache-dir \
    fastapi \
    "uvicorn[standard]" \
    openai \
    pyyaml \
    httpx \
    curl-cffi

# ── Copy vendored proxy source ─────────────────────────────────────────────────
COPY proxy/proxy_core.py /app/proxy_core.py
COPY proxy/claude_proxy.py /app/claude_proxy.py
COPY proxy/ollama-facade/server.py /app/ollama-facade/server.py

# ── Directory layout ───────────────────────────────────────────────────────────
RUN mkdir -p \
    /agentbox/.openclaw/workspace \
    /agentbox/.claude \
    /agentbox/data \
    /agentbox/backups \
    /agentbox/bin \
    /tmp/openclaw \
    && chown -R agentbox:agentbox /agentbox /tmp/openclaw

# ── Backup script ──────────────────────────────────────────────────────────────
COPY bin/backup.sh /agentbox/bin/backup.sh
RUN chmod +x /agentbox/bin/backup.sh \
    && chown agentbox:agentbox /agentbox/bin/backup.sh

# ── Supervisord + entrypoint ───────────────────────────────────────────────────
COPY supervisord.conf /etc/supervisor/conf.d/agentbox.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 3000 8319 11434

ENV HOME=/agentbox
ENV NODE_ENV=production
ENV OPENCLAW_CONFIG_PATH=/agentbox/.openclaw/openclaw.json
ENV OLLAMA_API_KEY=ollama-local
ENV LLM_PROXY_DB_PATH=/tmp/llm_proxy.db
ENV BACKUP_INTERVAL_HOURS=6
ENV BACKUP_KEEP_COUNT=10

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=30s \
    CMD pgrep -f openclaw-gateway && curl -sf http://localhost:11434/ || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
