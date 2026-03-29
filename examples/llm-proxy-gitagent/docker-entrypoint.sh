#!/bin/bash
# AgentBox + LLM Proxy + GitAgent — Entrypoint
set -e

echo "[entrypoint] AgentBox + LLM Proxy (claude_proxy.py)"
echo "──────────────────────────────────────────────────────"

# Load optional secrets file (populates CLAUDE_OAUTH_TOKEN if not set via env)
if [ -f "/agentbox/secrets/secrets.env" ]; then
    echo "[entrypoint] Loading secrets..."
    set -a
    # shellcheck disable=SC1091
    source /agentbox/secrets/secrets.env
    set +a
    echo "[entrypoint] Secrets loaded"
fi

# Write credentials.json for claude_proxy.py
# claude_proxy.py reads: $HOME/.claude/.credentials.json (HOME=/agentbox)
if [ -n "${CLAUDE_OAUTH_TOKEN:-}" ]; then
    CREDS_DIR="/agentbox/.claude"
    CREDS_FILE="$CREDS_DIR/.credentials.json"
    mkdir -p "$CREDS_DIR"
    cat > "$CREDS_FILE" <<EOF
{
  "claudeAiOauth": {
    "accessToken": "${CLAUDE_OAUTH_TOKEN}",
    "refreshToken": "",
    "expiresAt": 9999999999000
  }
}
EOF
    echo "[entrypoint] Wrote credentials.json (token: ${CLAUDE_OAUTH_TOKEN:0:20}...)"
else
    echo "[entrypoint] WARNING: CLAUDE_OAUTH_TOKEN not set — claude_proxy.py will fail to authenticate"
    echo "[entrypoint] Set CLAUDE_OAUTH_TOKEN in secrets/secrets.env or as an environment variable"
fi

# Ensure workspace and backups dirs exist (bind-mounts may be empty)
mkdir -p /agentbox/.openclaw/workspace /agentbox/backups

# Copy seed config into the volume so openclaw can do atomic renames
if [ -f "/agentbox/config-seed/openclaw.json" ]; then
    cp /agentbox/config-seed/openclaw.json /agentbox/.openclaw/openclaw.json
    echo "[entrypoint] Copied openclaw.json into volume"
fi

echo "[entrypoint] Starting supervisord..."
echo ""
exec "$@"
