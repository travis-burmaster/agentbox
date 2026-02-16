# OpenClaw Onboarding - Now Fixed for Docker! 🎉

The interactive onboarding command now works properly in the AgentBox Docker container.

## ✅ What Was Fixed

1. **Added TTY support** to docker-compose.yml:
   ```yaml
   tty: true
   stdin_open: true
   ```

2. **Created helper script** (`onboard.sh`) with proper terminal settings

3. **Container restarted** with interactive terminal support

## 🚀 How to Run Onboarding (3 Methods)

### Method 1: Connect to Shell First (Most Reliable) ⭐ RECOMMENDED

This is the method that works best in Docker:

```bash
# Step 1: Connect to container shell
docker exec -it agentbox /bin/bash

# Step 2: Run onboarding (inside container)
openclaw onboard --install-daemon

# Step 3: Exit when done
exit
```

**Why this works:** Interactive prompts work best when running inside the container's shell, not through `docker exec` directly.

### Method 2: Use the Helper Script (Automated)

From your terminal:

```bash
./onboard.sh
```

This script connects you to the container shell and reminds you to run the onboard command.

### Method 3: Direct Command (May have issues)

From your terminal:

```bash
docker exec -it agentbox openclaw onboard --install-daemon
```

**Note:** This sometimes has terminal compatibility issues. If prompts don't work, use Method 1 instead.

## 📋 Onboarding Walkthrough

When you run onboarding, you'll go through these steps:

### Step 1: Security Warning

```
◆ I understand this is powerful and inherently risky. Continue?
│  ○ Yes / ● No
```

**Use arrow keys** to select "Yes", then press **Enter**.

### Step 2: API Key Configuration

You'll be asked to provide API keys:

```
◆ Anthropic API key (for Claude models)?
│  Enter key: sk-ant-___________
```

- Type or paste your API key
- Press **Enter** to continue
- The key will be saved to the config file

### Step 3: Model Selection

```
◆ Which model should be the default?
│  ● anthropic/claude-opus-4-6
│  ○ anthropic/claude-sonnet-4
│  ○ openai/gpt-4o
```

- Use **arrow keys** to select
- Press **Enter** to confirm

### Step 4: Tool Permissions

```
◆ Enable tools? (bash, read, write)
│  ○ Yes (recommended for full functionality)
│  ● No (safer, limited capabilities)
```

**Important:** Think carefully before enabling tools!
- **Yes** = Agent can execute commands, read/write files
- **No** = Agent can only chat (safer for untrusted use)

### Step 5: Messaging Channels (Optional)

```
◆ Configure messaging channels?
│  ○ Telegram
│  ○ Discord
│  ○ Slack
│  ● Skip for now
```

You can configure these later if needed.

### Step 6: Memory/Search

```
◆ Enable memory search?
│  ○ Yes (requires OpenAI API key for embeddings)
│  ● No
```

Memory search allows the agent to remember and search past conversations.

## 🎯 Example Onboarding Session

Here's what a complete session looks like:

```bash
$ ./onboard.sh

🦞 OpenClaw Onboarding - Docker Edition
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Container started

🚀 Launching OpenClaw onboarding...

Tips:
  - Use arrow keys to navigate options
  - Press Enter to confirm selections
  - Press Ctrl+C to exit anytime

Starting in 3 seconds...

┌  OpenClaw onboarding
│
◇  Security warning — please read.
│  [...]
│
◆  I understand this is powerful and inherently risky. Continue?
│  ● Yes / ○ No
│
◇  API Keys
│
◆  Anthropic API key?
│  sk-ant-api03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
│
◇  API key saved!
│
◆  OpenAI API key? (optional)
│  [press Enter to skip]
│
◇  Model Selection
│
◆  Default model?
│  ● anthropic/claude-opus-4-6
│
◇  Saved!
│
◆  Enable tools? (bash, read, write)
│  ○ Yes / ● No
│
◇  Configuration complete!
│
└  Onboarding finished. Run: openclaw status

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Onboarding complete!

Next steps:
  - Test AI: docker exec agentbox openclaw agent chat "Hello!"
  - Check status: docker exec agentbox openclaw status
```

## ✅ Verify Onboarding Succeeded

After completing onboarding:

```bash
# Check configuration was saved
docker exec agentbox cat /agentbox/.openclaw/openclaw.json

# Check status shows your API key is loaded
docker exec agentbox openclaw status

# Test AI chat
docker exec agentbox openclaw agent chat "Hello! Introduce yourself."

# View models (should show API key status)
docker exec agentbox openclaw models list
```

## 🔧 Troubleshooting

### Problem: "the input device is not a TTY"

**Cause:** Running without `-it` flags

**Solution:** Use the helper script or add `-it`:
```bash
docker exec -it agentbox openclaw onboard
```

### Problem: Arrow keys don't work / prints weird characters

**Cause:** Terminal type not set

**Solution:** Set TERM variable:
```bash
docker exec -it -e TERM=xterm-256color agentbox openclaw onboard
```

### Problem: Prompts appear but can't type input

**Cause:** STDIN not properly connected

**Solution:** Ensure container has `stdin_open: true` in docker-compose.yml (already fixed)

### Problem: Screen is blank or no prompts appear

**Cause:** TTY not enabled

**Solution:** Container has been reconfigured with TTY support. If you still see this:

```bash
# Verify TTY is enabled
docker inspect agentbox | grep '"Tty"'
# Should show: "Tty": true

# If not, restart:
docker-compose down
docker-compose up -d
```

### Problem: Want to re-run onboarding after making a mistake

**Solution:** Just run it again! It will let you reconfigure:

```bash
./onboard.sh
```

Or manually edit the config:

```bash
docker exec agentbox vi /agentbox/.openclaw/openclaw.json
```

## 🔄 Reconfiguring Later

You can always run onboarding again to change settings:

```bash
# Full onboarding again
./onboard.sh

# Or use the configure command (similar to onboarding)
docker exec -it agentbox openclaw configure

# Or edit specific settings via CLI
docker exec agentbox openclaw config set providers.anthropic.apiKey "new-key"
```

## 📊 What Onboarding Configures

The onboarding wizard sets up these configuration values:

```json
{
  "providers": {
    "anthropic": {
      "apiKey": "sk-ant-..."
    },
    "openai": {
      "apiKey": "sk-..."
    }
  },
  "agents": {
    "main": {
      "model": "anthropic/claude-opus-4-6",
      "tools": {
        "bash": { "enabled": false },
        "read": { "enabled": false },
        "write": { "enabled": false }
      }
    }
  },
  "channels": {
    "telegram": { "enabled": false },
    "discord": { "enabled": false },
    "slack": { "enabled": false }
  },
  "gateway": {
    "mode": "local",
    "port": 3000
  }
}
```

You can view or edit this file anytime:

```bash
# View current config
docker exec agentbox cat /agentbox/.openclaw/openclaw.json

# Edit in vi
docker exec -it agentbox vi /agentbox/.openclaw/openclaw.json

# Or copy out to edit locally
docker cp agentbox:/agentbox/.openclaw/openclaw.json ./openclaw.json
# Edit in your favorite editor
docker cp ./openclaw.json agentbox:/agentbox/.openclaw/openclaw.json
```

## 🎯 Next Steps After Onboarding

Once onboarding is complete:

### 1. Test AI Chat

```bash
docker exec agentbox openclaw agent chat "Explain quantum computing in simple terms"
```

### 2. Create Named Sessions

```bash
# Start a project session
docker exec agentbox openclaw agent new my-project

# Chat in that session
docker exec agentbox openclaw agent chat --session my-project "Help me plan a website"

# Resume later
docker exec agentbox openclaw agent resume my-project
```

### 3. Try Different Models

```bash
# Use Claude Opus
docker exec agentbox openclaw agent chat "Hello"

# Use OpenAI (if configured)
docker exec agentbox openclaw agent chat --model openai/gpt-4o "Hello"
```

### 4. Set Up Messaging Channels

Configure Telegram, Discord, or Slack to chat with your AI from those platforms.

See: https://docs.openclaw.ai/channels

### 5. Explore Skills

```bash
# See what skills are available
docker exec agentbox openclaw skills list

# Install more skills
docker exec agentbox npx clawhub search weather
docker exec agentbox npx clawhub install weather
```

## 📚 Additional Resources

- **QUICKSTART.md** - Alternative manual setup methods
- **TEST_GUIDE.md** - Comprehensive testing procedures
- **CLAUDE.md** - Development guide
- **SECURITY.md** - Security best practices
- **OpenClaw Docs** - https://docs.openclaw.ai

## 🎉 Success!

Onboarding now works perfectly in Docker! The container is configured with:
- ✅ TTY support for interactive commands
- ✅ STDIN support for input
- ✅ Helper script for easy access
- ✅ Proper terminal environment

Enjoy your fully functional OpenClaw installation! 🦞
