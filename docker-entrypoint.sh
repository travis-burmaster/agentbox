#!/bin/bash
# AgentBox Docker Entrypoint
# Loads encrypted secrets and starts AgentBox

set -e

echo "🔒 AgentBox - Secure AI Agent Runtime"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Load encrypted secrets if they exist
if [ -f "/agentbox/secrets/secrets.env.age" ] && [ -f "/agentbox/secrets/agent.key" ]; then
    echo "🔐 Loading encrypted secrets..."
    
    # Check if age is available
    if command -v age &> /dev/null; then
        # Decrypt and export secrets (never writes to disk!)
        set -a  # Automatically export all variables
        while IFS= read -r line; do
            # Skip empty lines and comments
            if [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
                export "$line"
            fi
        done < <(age -d -i "/agentbox/secrets/agent.key" "/agentbox/secrets/secrets.env.age" 2>/dev/null || true)
        set +a
        
        echo "✅ Secrets loaded"
    else
        echo "⚠️  Warning: age not found, skipping secrets decryption"
    fi
else
    echo "⚠️  Warning: No encrypted secrets found"
    echo "   Expected: /agentbox/secrets/secrets.env.age"
    echo "   Key: /agentbox/secrets/agent.key"
fi

echo ""

# Ensure required directories exist
mkdir -p /agentbox/.openclaw/workspace
mkdir -p /agentbox/data
mkdir -p /agentbox/logs

# Check if config exists, if not use default
if [ ! -f "/agentbox/.openclaw/openclaw.json" ]; then
    echo "⚙️  No config found, checking for default..."
    if [ -f "/agentbox/.openclaw/openclaw.json" ]; then
        echo "✅ Using default config"
    else
        echo "⚠️  Warning: No config found, gateway may need setup"
    fi
fi

# Initialize workspace if needed
if [ ! -d "/agentbox/.openclaw/workspace" ]; then
    echo "📦 Initializing OpenClaw workspace..."
    OPENCLAW_HOME=/agentbox/.openclaw openclaw init || true
    echo "✅ Workspace initialized"
    echo ""
fi

# Set up firewall rules (if running as root in privileged mode)
if [ "$(id -u)" -eq 0 ] && command -v ufw &> /dev/null; then
    echo "🔥 Configuring firewall..."
    
    # Default deny
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow specific services (customize as needed)
    # ufw allow 3000/tcp  # AgentBox web UI (optional)
    
    # Enable firewall
    ufw --force enable
    
    echo "✅ Firewall configured"
    echo ""
fi

# Start audit logging (if available)
if command -v auditd &> /dev/null && [ "$(id -u)" -eq 0 ]; then
    echo "📝 Starting audit daemon..."
    service auditd start
    echo "✅ Audit logging enabled"
    echo ""
fi

echo "🚀 Starting AgentBox..."
echo ""

# ── Turso Memory Sync (optional durable memory backend) ──────────────────────
# If TURSO_URL and TURSO_TOKEN are set, pull memory from Turso on startup
# so ephemeral containers have full memory instantly.
# See: scripts/turso-memory-sync.sh and scripts/memory-sync-gitagent.sh
if [ -n "${TURSO_URL:-}" ] && [ -n "${TURSO_TOKEN:-}" ]; then
    echo "🧠 Pulling memory from Turso..."

    # Initialize schema (idempotent — safe to run every time)
    bash /agentbox/scripts/turso-memory-sync.sh init || \
        echo "⚠️  Warning: Turso schema init failed (continuing anyway)"

    # Pull SQLite memory (files, chunks, embedding_cache)
    bash /agentbox/scripts/turso-memory-sync.sh pull || \
        echo "⚠️  Warning: Turso SQLite pull failed (continuing anyway)"

    # Pull gitagent flat-file memory (context.md, dailylog.md, key-decisions.md)
    bash /agentbox/scripts/memory-sync-gitagent.sh pull || \
        echo "⚠️  Warning: Turso flat-file pull failed (continuing anyway)"

    echo "✅ Memory sync complete"
    echo ""

    # Register teardown hook — push memory back to Turso before container stops
    # Uses a trap on SIGTERM/SIGINT so it fires even on docker stop
    teardown_memory() {
        echo ""
        echo "🧠 Teardown: pushing memory to Turso..."
        bash /agentbox/scripts/turso-memory-sync.sh push || true
        bash /agentbox/scripts/memory-sync-gitagent.sh push || true
        echo "✅ Teardown memory sync complete"
    }
    trap teardown_memory SIGTERM SIGINT
fi

# Execute the main command
exec "$@"
