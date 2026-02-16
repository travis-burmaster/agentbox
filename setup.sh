#!/bin/bash
# AgentBox Quick Setup Script
# Bypasses onboarding and gets you running in 30 seconds

set -e

echo "🔒 AgentBox Quick Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if container is running
if ! docker ps | grep -q agentbox; then
    echo "❌ Container not running. Starting..."
    docker-compose up -d
    sleep 3
fi

echo "✅ Container is running"
echo ""

# Check for API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "⚠️  No ANTHROPIC_API_KEY found in environment"
    echo ""
    echo "To add your API key, choose one option:"
    echo ""
    echo "Option 1: Set environment variable (temporary)"
    echo "  export ANTHROPIC_API_KEY=sk-ant-your-key-here"
    echo "  ./setup.sh"
    echo ""
    echo "Option 2: Edit docker-compose.yml (permanent)"
    echo "  1. Open docker-compose.yml"
    echo "  2. Find the line: - ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY:-}"
    echo "  3. Change to: - ANTHROPIC_API_KEY=sk-ant-your-key-here"
    echo "  4. Save and run: docker-compose restart"
    echo ""
    echo "Get your API key from: https://console.anthropic.com/settings/keys"
    echo ""
    read -p "Press Enter to continue with basic tests (no AI)..."
else
    echo "✅ Found ANTHROPIC_API_KEY in environment"
    echo "   Restarting container to load API key..."
    docker-compose restart
    sleep 5
fi

echo ""
echo "🧪 Running Tests..."
echo ""

# Test 1: Version
echo "1️⃣  Version check:"
docker exec agentbox openclaw --version
echo ""

# Test 2: Gateway status
echo "2️⃣  Gateway status:"
docker exec agentbox openclaw status | head -20
echo ""

# Test 3: Available models
echo "3️⃣  Available models:"
docker exec agentbox openclaw models list
echo ""

# Test 4: Check if API key is working
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "4️⃣  Testing AI chat (this may take a few seconds)..."
    if docker exec agentbox openclaw agent chat "Say 'Hello! OpenClaw is working!' and nothing else." 2>&1 | grep -q "Hello"; then
        echo "✅ AI is working!"
    else
        echo "⚠️  AI test inconclusive. Try manually:"
        echo "   docker exec agentbox openclaw agent chat \"Hello!\""
    fi
else
    echo "4️⃣  Skipping AI test (no API key)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo ""
echo "📚 Next Steps:"
echo ""
echo "Chat with AI:"
echo "  docker exec agentbox openclaw agent chat \"Your message here\""
echo ""
echo "View status:"
echo "  docker exec agentbox openclaw status"
echo ""
echo "Run diagnostics:"
echo "  docker exec agentbox openclaw doctor"
echo ""
echo "See all available commands:"
echo "  docker exec agentbox openclaw --help"
echo ""
echo "📖 Full guides:"
echo "  - QUICKSTART.md - 5-minute setup guide"
echo "  - TEST_GUIDE.md - Complete testing procedures"
echo "  - CLAUDE.md - Development guide"
echo ""
