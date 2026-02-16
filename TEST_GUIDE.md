# OpenClaw Testing Guide for Docker

Complete guide to testing OpenClaw running in the AgentBox Docker container.

## 🔍 Quick Health Checks

```bash
# Container status
docker ps

# Gateway status
docker exec agentbox openclaw status

# System diagnostics
docker exec agentbox openclaw doctor

# Gateway probe (check reachability)
docker exec agentbox openclaw gateway probe

# View logs
docker logs agentbox
docker logs -f agentbox  # Follow mode
```

## 🧪 Basic Functionality Tests

### 1. Version & Installation

```bash
# Check OpenClaw version
docker exec agentbox openclaw --version

# View help
docker exec agentbox openclaw --help

# List all commands
docker exec agentbox openclaw help
```

### 2. Configuration Tests

```bash
# View current config
docker exec agentbox openclaw config get

# View specific setting
docker exec agentbox openclaw config get gateway.mode
docker exec agentbox openclaw config get gateway.port

# Set a config value
docker exec agentbox openclaw config set gateway.port 3000

# List all config keys
docker exec agentbox openclaw config list
```

### 3. Models & Providers

```bash
# List available models
docker exec agentbox openclaw models list

# Check model details
docker exec agentbox openclaw models info anthropic/claude-opus-4-6

# Test model availability (requires API key)
docker exec agentbox openclaw models test anthropic/claude-opus-4-6
```

### 4. Skills & Plugins

```bash
# List installed skills
docker exec agentbox openclaw skills list

# List loaded plugins
docker exec agentbox openclaw plugins list

# View plugin details
docker exec agentbox openclaw plugins info memory-core
```

### 5. Security Audit

```bash
# Basic security audit
docker exec agentbox openclaw security audit

# Deep security scan
docker exec agentbox openclaw security audit --deep

# Check permissions
docker exec agentbox ls -la /agentbox/.openclaw
```

## 🤖 AI Interaction Tests (Requires API Key)

### Setup: Add Your API Key

**Option 1: Environment Variable (Temporary)**

```bash
docker exec -e ANTHROPIC_API_KEY=sk-ant-your-key-here agentbox openclaw agent chat "Hello!"
```

**Option 2: Docker Compose (Permanent)**

Edit `docker-compose.yml`:

```yaml
environment:
  - NODE_ENV=production
  - ANTHROPIC_API_KEY=sk-ant-your-key-here  # Add this line
```

Then restart:

```bash
docker-compose restart
```

**Option 3: Encrypted Secrets (Recommended)**

See `secrets/README.md` for full setup. Quick version:

```bash
# Generate key
age-keygen -o secrets/agent.key
age-keygen -y secrets/agent.key > secrets/agent.key.pub

# Create secrets file
cat > secrets/secrets.env <<EOF
ANTHROPIC_API_KEY=sk-ant-your-key-here
EOF

# Encrypt
age -r $(cat secrets/agent.key.pub) -o secrets/secrets.env.age secrets/secrets.env
shred -u secrets/secrets.env

# Mount in docker-compose.yml
# Uncomment the secrets volume line:
# - ./secrets:/agentbox/secrets:ro
```

### Test AI Chat

```bash
# Simple chat test
docker exec agentbox openclaw agent chat "What is 2+2?"

# Chat with specific model
docker exec agentbox openclaw agent chat --model anthropic/claude-opus-4-6 "Tell me a joke"

# Interactive session
docker exec -it agentbox openclaw agent chat
# Type messages and press enter. Type 'exit' or Ctrl+D to quit.
```

### Test Agent Sessions

```bash
# Create a new session
docker exec agentbox openclaw agent new test-session

# List sessions
docker exec agentbox openclaw agent sessions

# Resume a session
docker exec agentbox openclaw agent resume test-session

# Delete a session
docker exec agentbox openclaw agent delete test-session
```

## 🔌 Channel Tests (Messaging Platforms)

### View Available Channels

```bash
# List all channels
docker exec agentbox openclaw channels list

# Check channel status
docker exec agentbox openclaw channels status
```

### Configure a Channel (Example: Telegram)

```bash
# Interactive configuration
docker exec -it agentbox openclaw configure

# Manual configuration
docker exec agentbox openclaw config set channels.telegram.enabled true
docker exec agentbox openclaw config set channels.telegram.botToken "YOUR_BOT_TOKEN"

# Test the channel
docker exec agentbox openclaw channels probe telegram
```

## 📊 Memory & Storage Tests

```bash
# Check memory status
docker exec agentbox openclaw memory status

# Deep memory check
docker exec agentbox openclaw memory status --deep

# List stored memories
docker exec agentbox openclaw memory list

# Search memories (requires embedding provider)
docker exec agentbox openclaw memory search "test query"
```

## 🔧 Advanced Tests

### Gateway WebSocket Test

```bash
# Install wscat locally
npm install -g wscat

# Connect to gateway (from host)
wscat -c ws://127.0.0.1:3000

# You should see a connection, but may need auth token
```

### Logs & Debugging

```bash
# View gateway logs
docker exec agentbox cat /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log

# Follow logs in real-time
docker exec agentbox tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log

# Check for errors
docker logs agentbox 2>&1 | grep -i error

# View all container logs
docker logs --tail 100 agentbox
```

### Performance Tests

```bash
# Check resource usage
docker stats agentbox

# Check processes in container
docker exec agentbox ps aux

# Check disk usage
docker exec agentbox df -h

# Check volume sizes
docker system df -v | grep agentbox
```

### Network Tests

```bash
# Check listening ports
docker exec agentbox netstat -tlnp 2>/dev/null | grep 3000

# Test from inside container
docker exec agentbox curl -v http://localhost:3000/ 2>&1 | head

# Test gateway from host
curl -v http://127.0.0.1:3000/ 2>&1 | head
```

## 🐛 Troubleshooting Tests

### Container Won't Start

```bash
# Check container status
docker ps -a | grep agentbox

# View container logs
docker logs agentbox

# Start in interactive mode for debugging
docker run -it --rm agentbox:latest /bin/bash
# Then inside: openclaw doctor
```

### Gateway Not Responding

```bash
# Check if gateway process is running
docker exec agentbox pgrep -f openclaw-gateway

# Check gateway specifically
docker exec agentbox ps aux | grep gateway

# Restart gateway (if needed)
docker-compose restart
```

### Configuration Issues

```bash
# Validate config
docker exec agentbox openclaw config validate

# Reset to defaults
docker exec agentbox openclaw config reset

# View config file directly
docker exec agentbox cat /agentbox/.openclaw/openclaw.json

# Check config backup
docker exec agentbox cat /agentbox/.openclaw/openclaw.json.bak
```

### Permission Issues

```bash
# Check file permissions
docker exec agentbox ls -la /agentbox/.openclaw

# Fix permissions (run doctor)
docker exec agentbox openclaw doctor --fix

# Manual permission fix
docker exec agentbox chmod 700 /agentbox/.openclaw/.openclaw
```

## 📈 Success Criteria

Your OpenClaw installation is working correctly if:

- ✅ `docker ps` shows container as "healthy"
- ✅ `openclaw status` shows gateway as "reachable"
- ✅ `openclaw doctor` has no CRITICAL issues
- ✅ `openclaw models list` shows available models
- ✅ With API key: `openclaw agent chat "test"` responds
- ✅ No error messages in `docker logs agentbox`

## 🔐 Security Testing

```bash
# Run security audit
docker exec agentbox openclaw security audit --deep

# Check for exposed secrets
docker exec agentbox openclaw security scan

# Verify firewall rules (if configured)
docker exec agentbox ufw status

# Check audit logs
docker exec agentbox cat /var/log/audit/audit.log 2>/dev/null || echo "Audit logging not active"
```

## 📝 Example Test Session

Here's a complete test workflow:

```bash
# 1. Verify container is healthy
docker ps

# 2. Check OpenClaw status
docker exec agentbox openclaw status

# 3. Run diagnostics
docker exec agentbox openclaw doctor

# 4. Fix any issues
docker exec agentbox openclaw doctor --fix

# 5. List available models
docker exec agentbox openclaw models list

# 6. Add API key (choose one method from above)
# Edit docker-compose.yml, then:
docker-compose restart

# 7. Test AI interaction
docker exec agentbox openclaw agent chat "What is the capital of France?"

# 8. Check session was created
docker exec agentbox openclaw agent sessions

# 9. View logs
docker logs agentbox | tail -20

# 10. Success! 🎉
```

## 🚀 Next Steps After Testing

Once testing is complete:

1. **Configure channels**: `openclaw configure` for Telegram, Discord, etc.
2. **Set up encrypted secrets**: See `secrets/README.md`
3. **Enable memory search**: Add OpenAI/Gemini key for embeddings
4. **Configure firewall**: See `SECURITY.md` for network isolation
5. **Set up backups**: Backup `/agentbox/.openclaw` volume regularly

## 📚 Resources

- **OpenClaw Docs**: https://docs.openclaw.ai
- **Troubleshooting**: https://docs.openclaw.ai/troubleshooting
- **FAQ**: https://docs.openclaw.ai/faq
- **AgentBox README**: `README.md`
- **Security Guide**: `SECURITY.md`
- **Gateway Status**: `GATEWAY_STATUS.md`
