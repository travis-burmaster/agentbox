# AgentBox Quick Start Guide

Fast track to getting OpenClaw running with AI in 5 minutes.

## ✅ Prerequisites

You should have already:
- Built the Docker image: `docker build -t agentbox:latest .`
- Started the container: `docker-compose up -d`
- Verified it's healthy: `docker ps` (shows "healthy")

## 🚀 5-Minute Setup

### Step 1: Verify Installation (30 seconds)

```bash
# Check container is running
docker ps

# Should show:
# STATUS: Up X minutes (healthy)
# PORTS: 127.0.0.1:3000->3000/tcp
```

### Step 2: Check Gateway Status (30 seconds)

```bash
docker exec agentbox openclaw status
```

You should see:
- ✅ Gateway: reachable
- ✅ Dashboard: http://127.0.0.1:3000/
- ✅ Model: anthropic/claude-opus-4-6

### Step 3: Add Your API Key (2 minutes)

**Choose ONE method:**

#### Method A: Environment Variable (Quick & Easy)

1. Edit `docker-compose.yml`:

```yaml
environment:
  - NODE_ENV=production
  - ANTHROPIC_API_KEY=sk-ant-your-actual-key-here  # Add this line
```

2. Restart:

```bash
docker-compose restart
```

#### Method B: Encrypted Secrets (Production-Ready)

```bash
# Generate encryption key
age-keygen -o secrets/agent.key
age-keygen -y secrets/agent.key > secrets/agent.key.pub

# Create secrets file
cat > secrets/secrets.env <<'EOF'
ANTHROPIC_API_KEY=sk-ant-your-actual-key-here
EOF

# Encrypt it
age -r $(cat secrets/agent.key.pub) -o secrets/secrets.env.age secrets/secrets.env

# Delete plaintext
shred -u secrets/secrets.env  # Linux
# OR
rm -P secrets/secrets.env     # macOS

# Update docker-compose.yml to mount secrets
# Uncomment this line under volumes:
#   - ./secrets:/agentbox/secrets:ro

# Restart
docker-compose restart
```

### Step 4: Test AI Interaction (1 minute)

```bash
# Simple test
docker exec agentbox openclaw agent chat "What is 2+2?"

# You should get a response from Claude!
```

### Step 5: Verify Everything Works (1 minute)

```bash
# Check status shows API key is working
docker exec agentbox openclaw status

# List sessions (should show your test chat)
docker exec agentbox openclaw agent sessions

# View logs
docker logs agentbox | tail -20
```

## ✅ Success Checklist

You're ready if:

- ✅ Container shows "healthy" in `docker ps`
- ✅ `openclaw status` shows gateway as "reachable"
- ✅ `openclaw agent chat "test"` returns an AI response
- ✅ No errors in `docker logs agentbox`

## 🎯 What's Next?

### Enable More Features

```bash
# Get OpenAI access too
# Add to docker-compose.yml environment:
OPENAI_API_KEY=sk-your-openai-key

# Test with OpenAI
docker exec agentbox openclaw agent chat --model openai/gpt-4o "Hello!"
```

### Configure Messaging Channels

**From your terminal** (needs interactive mode):

```bash
docker exec -it agentbox openclaw configure
```

This wizard will help you set up:
- 📱 Telegram bot
- 💬 Discord bot
- 💼 Slack integration
- 📧 Email notifications
- And 30+ other channels!

### Access the Dashboard

1. Open your browser
2. Go to: http://127.0.0.1:3000/
3. Note: Control UI assets aren't built in Docker (that's OK, CLI works fine)

## 🧪 Testing Commands

```bash
# System health
docker exec agentbox openclaw doctor

# List available models
docker exec agentbox openclaw models list

# Test a specific model
docker exec agentbox openclaw models test anthropic/claude-opus-4-6

# View configuration
docker exec agentbox sh -c 'cat /agentbox/.openclaw/openclaw.json'

# Check skills
docker exec agentbox openclaw skills list

# Security audit
docker exec agentbox openclaw security audit

# View logs
docker logs -f agentbox  # Press Ctrl+C to exit
```

## 💬 Example AI Conversations

### Simple Q&A

```bash
docker exec agentbox openclaw agent chat "Explain quantum computing in one sentence"
```

### Code Help

```bash
docker exec agentbox openclaw agent chat "Write a Python function to check if a number is prime"
```

### Create a Session

```bash
# Start a named session
docker exec agentbox openclaw agent new project-ideas

# Chat in that session
docker exec agentbox openclaw agent chat --session project-ideas "Give me 5 startup ideas"

# Resume later
docker exec agentbox openclaw agent resume project-ideas
```

### Using Different Models

```bash
# Claude Opus (default)
docker exec agentbox openclaw agent chat "Hello"

# OpenAI (if configured)
docker exec agentbox openclaw agent chat --model openai/gpt-4o "Hello"

# List all available models
docker exec agentbox openclaw models list
```

## 🔧 Troubleshooting

### "No API key found" Error

**Problem**: AI commands fail with authentication error

**Solution**: Add API key via docker-compose.yml (see Step 3 above), then:

```bash
docker-compose restart
docker exec agentbox openclaw status  # Verify key is loaded
```

### Container Shows "Unhealthy"

**Problem**: `docker ps` shows container as unhealthy

**Solution**: This was fixed in the latest version. Rebuild:

```bash
docker-compose down
docker build --no-cache -t agentbox:latest .
docker-compose up -d
```

### "Gateway Unreachable"

**Problem**: `openclaw status` shows gateway as unreachable

**Solution**: Check gateway logs:

```bash
docker logs agentbox | grep gateway
# Should see: "listening on ws://127.0.0.1:3000"
```

If not listening, restart:

```bash
docker-compose restart
```

### Interactive Commands Don't Work

**Problem**: `docker exec -it agentbox openclaw configure` fails

**Solution**: Run from your **Terminal app**, not through Claude Code:

1. Open macOS Terminal
2. Navigate to project: `cd ~/git/agentbox`
3. Run: `docker exec -it agentbox openclaw configure`

## 📚 Full Documentation

For complete details, see:

- **TEST_GUIDE.md** - Comprehensive testing procedures
- **CLAUDE.md** - Development guide for Claude Code
- **GATEWAY_STATUS.md** - Current deployment status
- **SECURITY.md** - Security architecture and best practices
- **secrets/README.md** - Encrypted secrets management
- **OpenClaw Docs** - https://docs.openclaw.ai

## 🆘 Getting Help

1. **Check logs**: `docker logs agentbox`
2. **Run diagnostics**: `docker exec agentbox openclaw doctor`
3. **View status**: `docker exec agentbox openclaw status --deep`
4. **GitHub Issues**: https://github.com/travis-burmaster/agentbox/issues
5. **OpenClaw Docs**: https://docs.openclaw.ai/troubleshooting

## 🎉 You're Ready!

Your AgentBox is now running with:

- ✅ Secure Docker container
- ✅ OpenClaw gateway (WebSocket + HTTP)
- ✅ AI model access (Claude Opus 4.6)
- ✅ Encrypted secrets support
- ✅ Health monitoring
- ✅ Persistent storage

Start chatting with AI and explore the 49 available skills! 🚀
