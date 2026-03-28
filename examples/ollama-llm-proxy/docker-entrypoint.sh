#!/bin/bash
# AgentBox + LLM Proxy — Entrypoint
set -e

echo "🤖 AgentBox + LLM Proxy (Ollama Facade)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Load secrets (OAuth token + any other credentials)
if [ -f "/agentbox/secrets/secrets.env" ]; then
    echo "🔐 Loading secrets..."
    set -a
    # shellcheck disable=SC1091
    source /agentbox/secrets/secrets.env
    set +a
    echo "✅ Secrets loaded"

    # Write OAuth token to the path claude_proxy.py reads from
    if [ -n "$CLAUDE_OAUTH_TOKEN" ]; then
        mkdir -p /agentbox/.claude
        echo "{\"claudeAiOauthToken\":\"$CLAUDE_OAUTH_TOKEN\"}" \
            > /agentbox/.claude/.credentials.json
        echo "✅ OAuth token written to /agentbox/.claude/.credentials.json"
    else
        echo "⚠️  CLAUDE_OAUTH_TOKEN not set — claude_proxy will use openclaw auth profiles"
    fi
else
    echo "⚠️  No secrets file found at /agentbox/secrets/secrets.env"
    echo "   Copy secrets/secrets.env.template → secrets/secrets.env and add your token"
fi

echo ""

# Ensure directories exist
mkdir -p /agentbox/.openclaw/workspace /agentbox/data /agentbox/logs

echo "🚀 Starting services..."
echo "   1. claude_proxy    :8319  (OAuth → Anthropic API)"
echo "   2. ollama-facade   :11434 (Ollama-compatible frontend)"
echo "   3. openclaw-gateway :3000  (AI agent)"
echo ""

exec "$@"
