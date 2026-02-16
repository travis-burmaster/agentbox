
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AgentBox** is a security-first AI agent framework designed for isolated VM deployment with encrypted secrets management. It's built on top of [OpenClaw](https://github.com/openclaw/openclaw), an open-source AI agent framework, adding enterprise-grade security features including:

- VM isolation (Docker/Vagrant/UTM/VirtualBox)
- Encrypted secrets using age encryption (ChaCha20-Poly1305)
- Network isolation with firewall rules
- Audit logging and security hardening
- Zero host access by default

**Critical naming distinction:**
- **AgentBox**: The overall security-focused project and Docker image name
- **openclaw**: The CLI command and core framework (NOT "agentbox")
- All commands inside containers use `openclaw`, not `agentbox`

## Repository Structure

### Core Architecture

```
agentbox/
├── agentfork/              # OpenClaw source code (core framework)
│   ├── src/               # TypeScript source
│   │   ├── cli/          # CLI wiring and command handlers
│   │   ├── commands/     # Command implementations
│   │   ├── gateway/      # Gateway service (daemon mode)
│   │   ├── agents/       # AI agent logic
│   │   ├── channels/     # Messaging channel integrations
│   │   ├── infra/        # Infrastructure code
│   │   └── config/       # Configuration management
│   ├── extensions/        # Plugin extensions (Telegram, Discord, etc.)
│   ├── dist/             # Compiled JavaScript output
│   ├── package.json      # OpenClaw dependencies
│   └── openclaw.mjs      # CLI entry point
│
├── Dockerfile            # Multi-stage Docker build
├── docker-compose.yml    # Production deployment config
├── docker-entrypoint.sh  # Container startup with secrets loading
├── config/
│   └── openclaw.json     # Default gateway configuration
├── scripts/
│   ├── load-secrets.sh   # Decrypt and load age-encrypted secrets
│   └── rotate-keys.sh    # Key rotation automation
├── secrets/
│   ├── README.md         # Secrets management guide
│   └── (*.age files)     # Encrypted secrets (safe to commit)
└── security/             # Firewall rules, SELinux, AppArmor profiles
```

### Key Files

- **Dockerfile**: Multi-stage build that compiles OpenClaw from source, installs security tools (age, ufw, fail2ban, auditd)
- **docker-entrypoint.sh**: Loads encrypted secrets on container startup, never writes plaintext to disk
- **config/openclaw.json**: Minimal gateway configuration (`gateway.mode=local`, port 3000)
- **agentfork/AGENTS.md**: OpenClaw contributor guidelines (symlinked as CLAUDE.md in agentfork/)

## Common Commands

### Docker Build & Run

```bash
# Build the image (5-10 minutes)
docker build -t agentbox:latest .

# Quick verification
docker run --rm agentbox:latest openclaw --version
docker run --rm agentbox:latest openclaw doctor

# Run with Docker Compose (recommended)
docker-compose up -d
docker-compose logs -f agentbox

# Manual run with persistent storage
docker run -d --name agentbox \
  -v agentbox-config:/agentbox/.openclaw \
  -v agentbox-data:/agentbox/data \
  -v agentbox-logs:/agentbox/logs \
  -p 127.0.0.1:3000:3000 \
  agentbox:latest

# Interactive shell access
docker run -it --rm agentbox:latest /bin/bash

# Clean rebuild (no cache)
docker build --no-cache -t agentbox:latest .
```

### OpenClaw CLI Commands (inside container)

```bash
# System diagnostics
docker run --rm agentbox:latest openclaw doctor
docker run --rm agentbox:latest openclaw status

# Configuration
docker run -it agentbox:latest openclaw configure
docker run --rm agentbox:latest openclaw config get
docker run --rm agentbox:latest openclaw config set gateway.mode local

# Models and skills
docker run --rm agentbox:latest openclaw models list
docker run --rm agentbox:latest openclaw skills list

# Security audit
docker run --rm agentbox:latest openclaw security audit

# Gateway service
docker run --rm agentbox:latest openclaw gateway run  # Foreground mode (no systemd)
```

### OpenClaw Development (agentfork/)

The agentfork/ directory is the OpenClaw source. If modifying OpenClaw itself:

```bash
cd agentfork/

# Install dependencies (requires pnpm)
pnpm install

# Build OpenClaw
pnpm build

# Run in development mode
pnpm dev

# Testing
pnpm test                    # Unit tests
pnpm test:coverage           # With coverage report
pnpm test:e2e               # End-to-end tests
pnpm test:live              # Live API tests (requires keys)

# Linting and formatting
pnpm check                  # Format check + typecheck + lint
pnpm format                 # Format check (oxfmt)
pnpm format --write         # Auto-fix formatting
pnpm lint                   # Lint (oxlint)
pnpm lint:fix               # Auto-fix linting
pnpm tsgo                   # TypeScript checks
```

**Note**: OpenClaw requires Node.js 22+ and uses pnpm as package manager.

### Secrets Management

```bash
# Generate encryption key (ONCE, backup safely!)
age-keygen -o secrets/agent.key
age-keygen -y secrets/agent.key > secrets/agent.key.pub

# Create and encrypt secrets
cat > secrets/secrets.env <<EOF
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
TELEGRAM_BOT_TOKEN=...
EOF

age -r $(cat secrets/agent.key.pub) -o secrets/secrets.env.age secrets/secrets.env
shred -u secrets/secrets.env  # Delete plaintext immediately!

# Load secrets (decrypts in-memory, never writes to disk)
source scripts/load-secrets.sh

# Rotate keys (every 6-12 months)
./scripts/rotate-keys.sh
```

## Architecture & Design

### Multi-Layer Security Model

1. **VM Isolation Layer**: Agent runs in isolated container/VM with no host filesystem access
2. **Encrypted Secrets Layer**: All secrets encrypted with age (ChaCha20-Poly1305), decrypted only in-memory
3. **Network Isolation Layer**: Firewall allowlists for API endpoints (Anthropic, OpenAI, etc.)
4. **Audit Logging Layer**: Immutable append-only logs for all agent actions
5. **Application Security Layer**: Tool allowlists, SELinux/AppArmor profiles

### OpenClaw Gateway Architecture

OpenClaw operates in two modes:

- **CLI mode**: Direct command execution (`openclaw <command>`)
- **Gateway mode**: Long-running service that manages agent sessions
  - `openclaw gateway run`: Foreground mode (Docker-friendly, no systemd)
  - `openclaw gateway start`: Background daemon mode (requires systemd, not used in containers)

The gateway exposes an HTTP API on port 3000 (localhost only) for:
- Agent interaction endpoints
- Health checks (`/health`)
- Configuration management
- Session state persistence

### Key Components

- **Gateway** (`src/gateway/`): HTTP server, session management, routing
- **Agents** (`src/agents/`): AI model integration, tool execution, conversation handling
- **Channels** (`src/channels/`, `extensions/*/`): Messaging platform integrations (Telegram, Discord, Slack, etc.)
- **Config** (`src/config/`): JSON-based configuration with schema validation
- **Infra** (`src/infra/`): Database, file operations, logging, utilities
- **Security** (`src/security/`): Access control, audit logging, allowlists

### Extension System

OpenClaw supports plugins/extensions in `extensions/*/`:
- Each extension is a workspace package with its own `package.json`
- Extensions for messaging platforms (BlueBubbles, Discord, Feishu, Google Chat, iMessage, IRC, Line, Matrix, Mattermost, MS Teams, Nextcloud Talk, Nostr, Signal, Slack, Telegram, Twitch, WhatsApp, Zalo)
- Extensions for memory (memory-core, memory-lancedb, llm-task)
- Extensions for authentication (google-antigravity-auth, minimax-portal-auth)

## Development Workflow

### Making Changes to AgentBox

1. **Modify Docker configuration**: Edit `Dockerfile`, `docker-compose.yml`, or `docker-entrypoint.sh`
2. **Rebuild image**: `docker build -t agentbox:latest .`
3. **Test locally**: `docker-compose up -d && docker-compose logs -f`
4. **Verify health**: `curl http://127.0.0.1:3000/health`

### Making Changes to OpenClaw Core

1. **Enter agentfork directory**: `cd agentfork/`
2. **Make code changes** in `src/`
3. **Build**: `pnpm build`
4. **Test**: `pnpm test`
5. **Lint**: `pnpm check`
6. **Rebuild Docker image** to include changes: `cd .. && docker build -t agentbox:latest .`

### Git Workflow

- **Safe to commit**: `*.age` (encrypted secrets), `*.pub` (public keys)
- **NEVER commit**: `agent.key` (private key), `*.env` (plaintext secrets)
- Use `scripts/committer "<msg>" <file...>` for scoped commits (OpenClaw convention)
- Pre-commit hooks: Run checks before commits (install with `prek install` in agentfork/)

## Configuration

### Environment Variables

```bash
# OpenClaw paths
OPENCLAW_HOME=/agentbox/.openclaw
OPENCLAW_WORKSPACE=/agentbox/.openclaw/workspace
OPENCLAW_CONFIG_PATH=/agentbox/.openclaw/openclaw.json

# Runtime mode
NODE_ENV=production

# API keys (provide via encrypted secrets or environment)
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
TELEGRAM_BOT_TOKEN=...
```

### Gateway Configuration (openclaw.json)

```json
{
  "gateway": {
    "mode": "local",
    "port": 3000
  }
}
```

Modify with:
```bash
openclaw config set gateway.port 3001
openclaw config get
```

## Security Considerations

- **Secrets**: Always use age encryption. Never commit `agent.key` or plaintext `.env` files.
- **Network**: Bind ports to `127.0.0.1` only (localhost), never `0.0.0.0` (all interfaces).
- **Volumes**: Mount secrets as read-only (`:ro`) when possible.
- **Updates**: Regular dependency updates (`docker pull`, `pnpm update` in agentfork/).
- **Firewall**: Configure UFW/iptables allowlists for API endpoints in production.
- **Audit logs**: Monitor `/agentbox/logs` and `/var/log/audit/` for security events.
- **Key rotation**: Rotate encryption keys every 6-12 months using `scripts/rotate-keys.sh`.

## Troubleshooting

### Docker build fails with "module not found"
- Try clean build: `docker build --no-cache -t agentbox:latest .`
- Ensure OpenClaw source is complete in `agentfork/`

### Container exits immediately
- Default CMD runs gateway service; override for debugging:
  ```bash
  docker run -it --rm agentbox:latest /bin/bash
  docker run --rm agentbox:latest openclaw doctor
  ```

### Gateway won't start
- Check config: `docker run --rm agentbox:latest openclaw config get`
- Check logs: `docker logs agentbox 2>&1 | grep -i error`
- Verify mode is set: `openclaw config set gateway.mode local`

### "command not found: openclaw"
- The CLI is named `openclaw`, not `agentbox`
- Correct: `docker run --rm agentbox:latest openclaw --version`
- Wrong: `docker run --rm agentbox:latest agentbox --version`

## Resources

- **AgentBox README**: `README.md` (project overview, quick start)
- **Security Architecture**: `SECURITY.md` (threat model, security layers)
- **Secrets Guide**: `secrets/README.md` (age encryption workflows)
- **Gateway Status**: `GATEWAY_STATUS.md` (current implementation status)
- **OpenClaw Docs**: https://docs.openclaw.ai
- **OpenClaw Source**: https://github.com/openclaw/openclaw
