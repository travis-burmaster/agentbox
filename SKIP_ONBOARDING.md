# Skip Onboarding - Get OpenClaw Working in 30 Seconds

The interactive onboarding can be problematic in Docker containers. Here's how to bypass it completely.

## 🚀 Quick Setup (Choose One Method)

### Method 1: Automated Setup Script (Easiest)

```bash
# 1. Set your API key
export ANTHROPIC_API_KEY=sk-ant-your-key-here

# 2. Run the setup script
./setup.sh
```

That's it! The script will:
- ✅ Start the container if needed
- ✅ Load your API key
- ✅ Run tests to verify everything works
- ✅ Show you next steps

### Method 2: Manual Setup (3 steps)

**Step 1: Add API Key to docker-compose.yml**

Edit `docker-compose.yml` and find this section:

```yaml
environment:
  - NODE_ENV=production
  - OPENCLAW_HOME=/agentbox/.openclaw
  - OPENCLAW_WORKSPACE=/agentbox/.openclaw/workspace
  - OPENCLAW_CONFIG_PATH=/agentbox/.openclaw/openclaw.json

  # Add your API keys here:
  - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}  # <-- Change this line
```

Change the last line to:

```yaml
  - ANTHROPIC_API_KEY=sk-ant-your-actual-key-here
```

**Step 2: Restart the Container**

```bash
docker-compose restart
```

**Step 3: Test It**

```bash
docker exec agentbox openclaw agent chat "Hello! Can you introduce yourself?"
```

### Method 3: Environment Variable (No File Edits)

```bash
# Set the API key in your shell
export ANTHROPIC_API_KEY=sk-ant-your-key-here

# Restart with environment variable
docker-compose down
docker-compose up -d

# Test
docker exec agentbox openclaw agent chat "Hello!"
```

## 🧪 Verify It's Working

Run these commands to verify everything is set up:

```bash
# 1. Check container is healthy
docker ps
# Should show: STATUS = Up X minutes (healthy)

# 2. Check gateway is reachable
docker exec agentbox openclaw status
# Should show: Gateway = reachable

# 3. Test AI
docker exec agentbox openclaw agent chat "What is 2+2?"
# Should get an AI response

# 4. Check for errors
docker logs agentbox | grep -i error
# Should be empty or only minor warnings
```

## ❓ What About All Those Onboarding Settings?

You can configure them later as needed. Here's what onboarding sets up and how to do it manually:

### API Keys (Required for AI)

**Via docker-compose.yml:**
```yaml
environment:
  - ANTHROPIC_API_KEY=sk-ant-...
  - OPENAI_API_KEY=sk-...
```

**Via CLI:**
```bash
docker exec agentbox openclaw config set providers.anthropic.apiKey "sk-ant-..."
```

### Model Selection

```bash
# Set default model
docker exec agentbox openclaw config set agents.main.model "anthropic/claude-opus-4-6"

# List available models
docker exec agentbox openclaw models list
```

### Tool Permissions (Enable carefully!)

```bash
# Enable specific tools
docker exec agentbox openclaw config set agents.main.tools.bash.enabled true
docker exec agentbox openclaw config set agents.main.tools.read.enabled true
docker exec agentbox openclaw config set agents.main.tools.write.enabled true

# View current tool settings
docker exec agentbox openclaw config get agents.main.tools
```

### Messaging Channels (Optional)

**Telegram:**
```bash
docker exec agentbox openclaw config set channels.telegram.enabled true
docker exec agentbox openclaw config set channels.telegram.botToken "YOUR_BOT_TOKEN"
```

**Discord:**
```bash
docker exec agentbox openclaw config set channels.discord.enabled true
docker exec agentbox openclaw config set channels.discord.botToken "YOUR_BOT_TOKEN"
```

**Slack:**
```bash
docker exec agentbox openclaw config set channels.slack.enabled true
docker exec agentbox openclaw config set channels.slack.botToken "xoxb-YOUR-TOKEN"
```

### Memory/Search (Optional)

```bash
# Enable with OpenAI embeddings
docker exec agentbox openclaw config set agents.defaults.memorySearch.enabled true
docker exec agentbox openclaw config set agents.defaults.memorySearch.provider "openai"

# Requires OPENAI_API_KEY in environment
```

### Security Settings

```bash
# Run security audit
docker exec agentbox openclaw security audit

# Fix issues automatically
docker exec agentbox openclaw security audit --fix

# Set permission level
docker exec agentbox openclaw config set agents.main.security.riskLevel "medium"
```

## 🔒 Using Encrypted Secrets (Recommended for Production)

Instead of plain text API keys in docker-compose.yml, use age encryption:

**1. Generate encryption key:**

```bash
age-keygen -o secrets/agent.key
age-keygen -y secrets/agent.key > secrets/agent.key.pub
```

**2. Create secrets file:**

```bash
cat > secrets/secrets.env <<'EOF'
ANTHROPIC_API_KEY=sk-ant-your-key-here
OPENAI_API_KEY=sk-your-openai-key
EOF
```

**3. Encrypt it:**

```bash
age -r $(cat secrets/agent.key.pub) -o secrets/secrets.env.age secrets/secrets.env
shred -u secrets/secrets.env  # Delete plaintext
```

**4. Mount in docker-compose.yml:**

Uncomment this line in `docker-compose.yml`:

```yaml
volumes:
  - ./secrets:/agentbox/secrets:ro  # Uncomment this
```

**5. Restart:**

```bash
docker-compose restart
```

The container will automatically decrypt and load secrets on startup!

## ✅ You're Ready!

Once your API key is configured, you can:

```bash
# Chat with AI
docker exec agentbox openclaw agent chat "Help me brainstorm project ideas"

# Create named sessions
docker exec agentbox openclaw agent new my-project

# Resume sessions
docker exec agentbox openclaw agent resume my-project

# List all sessions
docker exec agentbox openclaw agent sessions

# Use different models
docker exec agentbox openclaw agent chat --model openai/gpt-4o "Hello"

# Get help
docker exec agentbox openclaw --help
```

## 🆘 Still Having Issues?

**Problem: "No API key found"**

Solution: Make sure you restarted after adding the key:
```bash
docker-compose restart
docker exec agentbox openclaw status  # Should show key is loaded
```

**Problem: "Connection refused" or "Gateway unreachable"**

Solution: Check gateway is running:
```bash
docker logs agentbox | grep "listening on"
# Should show: listening on ws://127.0.0.1:3000
```

**Problem: Interactive commands hang**

Solution: Don't use interactive commands in Docker. Use scripted alternatives:
- ❌ `openclaw onboard` (interactive, won't work)
- ✅ `openclaw config set ...` (scriptable, works great)

**Problem: Want to see the full config**

```bash
docker exec agentbox cat /agentbox/.openclaw/openclaw.json
```

## 📚 Learn More

- **QUICKSTART.md** - Complete 5-minute setup guide
- **TEST_GUIDE.md** - Comprehensive testing procedures
- **secrets/README.md** - Encrypted secrets management
- **SECURITY.md** - Security best practices
- **OpenClaw Docs** - https://docs.openclaw.ai

---

**Bottom line:** You don't need onboarding! Just add your API key and start chatting with AI. Configure other features as you need them. 🚀
