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

# Initialize AgentBox workspace if not already done
if [ ! -d "/agentbox/.agentbox/workspace" ]; then
    echo "📦 Initializing AgentBox workspace..."
    agentbox init
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

# Execute the main command
exec "$@"
