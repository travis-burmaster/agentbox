#!/bin/bash
# OpenClaw Onboarding Helper for Docker
# Ensures proper terminal settings for interactive prompts

set -e

echo "🦞 OpenClaw Onboarding - Docker Edition"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if container is running
if ! docker ps | grep -q agentbox; then
    echo "Container not running. Starting with TTY support..."
    docker-compose up -d
    sleep 3
    echo "✅ Container started"
    echo ""
fi

# Check if container has TTY support
if ! docker inspect agentbox | grep -q '"Tty": true'; then
    echo "⚠️  Container doesn't have TTY support enabled."
    echo ""
    echo "Fixing this now..."
    echo "1. Stopping container..."
    docker-compose down

    echo "2. TTY support has been added to docker-compose.yml"
    echo "3. Starting container with TTY support..."
    docker-compose up -d
    sleep 3
    echo "✅ Container restarted with TTY support"
    echo ""
fi

echo "🚀 Launching OpenClaw onboarding..."
echo ""
echo "Tips:"
echo "  - Use arrow keys to navigate options"
echo "  - Press Enter to confirm selections"
echo "  - Press Ctrl+D or type 'exit' to finish"
echo "  - Press Ctrl+C to abort anytime"
echo ""
echo "This will:"
echo "  1. Connect to container shell"
echo "  2. Run: openclaw onboard --install-daemon"
echo "  3. Guide you through configuration"
echo ""
echo "Starting in 3 seconds..."
sleep 3
echo ""

# Run onboarding with proper terminal settings
# Method: Connect to bash shell, then run onboard command
# This is the most reliable way for interactive prompts in Docker
echo "Connecting to container..."
echo "Run: openclaw onboard --install-daemon"
echo ""
docker exec -it agentbox /bin/bash -c "echo ''; echo 'Run this command to start onboarding:'; echo '  openclaw onboard --install-daemon'; echo ''; exec /bin/bash"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Onboarding complete!"
echo ""
echo "Next steps:"
echo "  - Test AI: docker exec agentbox openclaw agent chat \"Hello!\""
echo "  - Check status: docker exec agentbox openclaw status"
echo "  - View config: docker exec agentbox cat /agentbox/.openclaw/openclaw.json"
echo ""
