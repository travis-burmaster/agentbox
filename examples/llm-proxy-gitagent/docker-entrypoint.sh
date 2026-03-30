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

# Ensure gateway auth token is set (openclaw requires it when auth.mode=token)
if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    export OPENCLAW_GATEWAY_TOKEN="$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)"
    echo "[entrypoint] Generated random OPENCLAW_GATEWAY_TOKEN"
else
    echo "[entrypoint] Using provided OPENCLAW_GATEWAY_TOKEN"
fi

# Seed openclaw.json on first boot (named volume starts empty; openclaw needs this file to start)
mkdir -p /agentbox/.openclaw
if [ ! -f "/agentbox/.openclaw/openclaw.json" ] && [ -f "/agentbox/host-config/openclaw.json" ]; then
    cp /agentbox/host-config/openclaw.json /agentbox/.openclaw/openclaw.json
    echo "[entrypoint] Seeded openclaw.json from host-config"
fi

# Ensure workspace and backups dirs exist (bind-mounts may be empty)
mkdir -p /agentbox/.openclaw/workspace /agentbox/backups

# Inject Telegram channel config directly into openclaw.json (no gateway process needed)
if [ -n "${TELEGRAM_TOKEN:-}" ]; then
    echo "[entrypoint] Injecting Telegram channel config..."
    python3 - <<PYEOF
import json, os, sys

config_path = "/agentbox/.openclaw/openclaw.json"
token = os.environ["TELEGRAM_TOKEN"]

try:
    with open(config_path) as f:
        cfg = json.load(f)
except Exception as e:
    print(f"[entrypoint] Could not read openclaw.json: {e}", file=sys.stderr)
    sys.exit(0)

cfg.setdefault("channels", {})["telegram"] = {
    "enabled": True,
    "dmPolicy": "pairing",
    "botToken": token,
    "groups": {"*": {"requireMention": True}},
    "groupPolicy": "allowlist",
    "streaming": "partial",
}

with open(config_path, "w") as f:
    json.dump(cfg, f, indent=2)

print("[entrypoint] Telegram channel configured")
PYEOF
else
    echo "[entrypoint] TELEGRAM_TOKEN not set — Telegram channel skipped"
fi

# Kill any stray openclaw processes left over from config setup (before supervisord takes over)
pkill -f openclaw-gateway 2>/dev/null || true
sleep 1

echo "[entrypoint] Starting supervisord..."
echo ""
exec "$@"
