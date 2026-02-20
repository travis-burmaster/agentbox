
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

### Secrets Management (AES-256-CBC encrypted bundle)

All secrets for the A2A Cloud Run image live in a single encrypted file
(`secrets_encrypted.enc`) committed to the **private workspace repo**
(separate from this repo). Only 2 secrets ever touch Google Secret Manager.

```bash
# ── One-time setup ────────────────────────────────────────────────────────────
# 1. Copy the example secrets template
cp secrets.example.json secrets.json

# 2. Fill in values (see secrets.example.json for all keys)
#    Required: anthropic_api_key, openclaw_gateway_token
#    Optional: smtp_*, notion_secret, telegram_bot_token, + any skill secrets

# 3. Encrypt → produces secrets_encrypted.enc
ENCRYPTION_KEY="your-strong-passphrase" ./scripts/encrypt-secrets.sh
# or: ./scripts/encrypt-secrets.sh  (prompts for key)

# 4. Commit the encrypted file to your workspace repo
#    NEVER commit secrets.json — it is gitignored

# ── Adding a new skill's secrets ─────────────────────────────────────────────
./scripts/decrypt-secrets.sh          # decrypt to secrets.json
# edit secrets.json → add new key (e.g. "my_skill_api_key": "...")
./scripts/encrypt-secrets.sh          # re-encrypt
# commit secrets_encrypted.enc to workspace repo + push
# redeploy Cloud Run — no service.yaml changes needed

# ── Decrypt for local inspection ──────────────────────────────────────────────
ENCRYPTION_KEY="your-key" ./scripts/decrypt-secrets.sh
cat secrets.json   # inspect
shred -u secrets.json  # clean up
```

**Encryption details:**
- Algorithm: AES-256-CBC with salt, PBKDF2, 100,000 iterations
- Compatible with standard openssl (no extra tools needed)
- `secrets.json` and `secrets_decrypted.json` are both gitignored

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

**Cloud Run A2A image** — only 3 vars needed at the Cloud Run level:

```bash
# Plain env var (service.yaml)
WORKSPACE_REPO=owner/your-workspace-repo   # GitHub path, no .git suffix

# From Google Secret Manager
GITHUB_TOKEN=github_pat_xxxx               # read+write access to WORKSPACE_REPO
ENCRYPTION_KEY=your-passphrase             # decrypts secrets_encrypted.enc
```

All other credentials (Anthropic key, SMTP, Notion, etc.) are injected at
runtime from `secrets_encrypted.enc` inside the workspace repo. See
`secrets.example.json` for the full structure.

**Base AgentBox image** (local VM):

```bash
OPENCLAW_HOME=/agentbox/.openclaw
OPENCLAW_WORKSPACE=/agentbox/.openclaw/workspace
OPENCLAW_CONFIG_PATH=/agentbox/.openclaw/openclaw.json
NODE_ENV=production
AGENTBOX_BACKEND=cli
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

- **Secrets (Cloud Run)**: Use `scripts/encrypt-secrets.sh` to produce `secrets_encrypted.enc`. Never commit `secrets.json`. Only `GITHUB_TOKEN` + `ENCRYPTION_KEY` touch Secret Manager.
- **Secrets (local VM)**: Use age encryption for the base AgentBox image (`secrets/*.age`). Never commit `agent.key` or plaintext `.env` files.
- **Network**: Gateway binds to loopback (`:3000` internal); only FastAPI port `:8080` is exposed externally on Cloud Run.
- **Key rotation**: Rotate `ENCRYPTION_KEY` by decrypting with old key, re-encrypting with new key, updating Secret Manager, redeploying.
- **Workspace repo**: Set `minScale: 1` on Cloud Run to avoid concurrent memory push conflicts.
- **PAT scope**: Use a fine-grained GitHub PAT scoped to only the workspace repo with read+write Contents permission.
- **Shred**: `docker-entrypoint.sh` runs `shred -u` on the decrypted secrets file before handing off to supervisord — no plaintext remains on disk.
- **Updates**: Regular dependency updates (`pnpm update` in agentfork/, `openclaw@latest` version pin in Dockerfile).

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

## A2A Layer for Gemini Enterprise (Cloud Run)

An A2A wrapper lives under `a2a/` so Gemini Enterprise can call AgentBox as a
sub-agent over JSON-RPC. The image is **self-contained** — it bundles the
OpenClaw gateway + FastAPI A2A wrapper in a single container managed by
`supervisord`. All configuration and secrets are pulled at startup from a
**private GitHub workspace repo**; nothing sensitive is baked into the image.

### Repository layout

```
a2a/
├── server.py              # FastAPI A2A server (tasks/send, tasks/get, /health)
├── agent_card.json        # A2A agent card (served at /.well-known/agent.json)
├── Dockerfile.a2a         # Cloud Run image (ubuntu:22.04, Node 22, gh CLI, jq)
├── docker-entrypoint.sh   # Boot sequence (see below)
├── supervisord.conf       # Process manager: uvicorn (8080) + openclaw gateway (3000)
├── requirements.txt       # Python deps (fastapi, uvicorn, google-auth, httpx)
└── cloud_run/
    ├── service.yaml       # Cloud Run manifest template
    ├── cloudbuild.yaml    # Build + deploy pipeline
    └── setup.sh           # One-time GCP bootstrap (APIs/IAM/secrets)

scripts/
├── encrypt-secrets.sh     # Encrypt secrets.json → secrets_encrypted.enc
└── decrypt-secrets.sh     # Decrypt secrets_encrypted.enc → secrets.json (local only)

secrets.example.json       # Template — copy to secrets.json, fill in, encrypt
.env.example               # Documents the 3 env vars needed
```

### Boot sequence (`docker-entrypoint.sh`)

```
1. Validate WORKSPACE_REPO, GITHUB_TOKEN, ENCRYPTION_KEY env vars
2. Auth gh CLI + configure git with GITHUB_TOKEN
3. git clone --depth=1 <WORKSPACE_REPO> → /agentbox/.openclaw/workspace
   (or git pull if warm instance / persistent volume)
4. openssl decrypt secrets_encrypted.enc → /agentbox/secrets_decrypted.json
5. Extract anthropic_api_key + openclaw_gateway_token from JSON
6. Export all other keys as env vars (auto-available to skills at runtime)
7. openclaw onboard --non-interactive --accept-risk (skipped if already configured)
8. shred -u /agentbox/secrets_decrypted.json  ← no plaintext left on disk
9. exec supervisord → starts uvicorn (8080) + openclaw gateway (3000)
```

### Workspace repo (separate private GitHub repo)

The workspace repo (`WORKSPACE_REPO=owner/repo`) is **not** this agentbox repo.
It contains:
- All OpenClaw workspace files: `SOUL.md`, `USER.md`, `MEMORY.md`, `AGENTS.md`, etc.
- `memory/` directory (agent memory — committed by agent on write)
- `scripts/` (Python scripts: options scanner, yfinance, etc.)
- `secrets_encrypted.enc` (AES-256-CBC encrypted secrets bundle)

The agent commits and pushes memory changes back to this repo during operation
so state persists across Cloud Run cold starts.

### Environment variables

| Variable | Source | Purpose |
|---|---|---|
| `WORKSPACE_REPO` | `.env` / `service.yaml` plain env | GitHub path (`owner/repo`) |
| `GITHUB_TOKEN` | Google Secret Manager | Clone + push workspace repo |
| `ENCRYPTION_KEY` | Google Secret Manager | Decrypt `secrets_encrypted.enc` |

**Only 2 secrets ever touch Google Secret Manager.** All other credentials
(Anthropic key, SMTP, Notion, Telegram, skill keys, etc.) live inside
`secrets_encrypted.enc` in the workspace repo.

### secrets_encrypted.enc structure (`secrets.example.json`)

```json
{
  "anthropic_api_key": "sk-ant-...",
  "openclaw_gateway_token": "...",
  "smtp_host": "mail.smtp2go.com",
  "smtp_port": "587",
  "smtp_user": "...",
  "smtp_password": "...",
  "smtp_from": "bot@yourdomain.com",
  "notion_secret": "secret_...",
  "telegram_bot_token": "...",
  "custom_skill_api_key": ""    ← add new skill secrets here
}
```

All keys not in the reserved set are automatically exported as uppercase env vars
(e.g. `custom_skill_api_key` → `CUSTOM_SKILL_API_KEY`).

### Headless onboarding

OpenClaw supports fully non-interactive setup via CLI flags:

```bash
openclaw onboard \
  --non-interactive --accept-risk \
  --flow manual --mode local \
  --auth-choice anthropic-api-key \
  --anthropic-api-key "${ANTHROPIC_API_KEY}" \
  --gateway-auth token \
  --gateway-token "${OPENCLAW_GATEWAY_TOKEN}" \
  --gateway-bind loopback \
  --workspace /agentbox/.openclaw/workspace \
  --skip-channels --skip-daemon \
  --skip-skills --skip-ui --skip-health \
  --no-install-daemon
```

The entrypoint skips this step if `agents.defaults.model.primary` is already
configured (idempotent — safe on warm restarts).

### Protocol behavior

- `POST /` supports `tasks/send` and `tasks/get`
- Response format follows A2A JSON-RPC envelope with artifacts
- Streaming via Server-Sent Events when `params.stream=true`
- Errors returned as A2A JSON-RPC `error` objects (not raw stack traces)
- `/health` endpoint checks uvicorn liveness + (optionally) gateway TCP reachability

### Security and IAM

- Cloud Run deployed with `--no-allow-unauthenticated` (IAM only)
- Validates Google-signed identity token; checks caller SA via `EXPECTED_CALLER_SA`
- Set `EXPECTED_AUDIENCE` to the Cloud Run service URL
- Do not chain inbound Gemini bearer tokens to downstream services
- For downstream auth use Workload Identity + Secret Manager
- `minScale: 1` recommended (personal assistant — single instance avoids git merge conflicts on memory push)

### Runtime constraints

- Task timeout: 55 minutes (fits Cloud Run 60-minute ceiling)
- Wrapper is stateless; session state persists via workspace repo git commits
- Gateway runs on `:3000` (internal only); only `:8080` (FastAPI) is exposed

### Slack integration

OpenClaw supports two Slack modes. **Socket Mode is recommended for Cloud Run.**

| Mode | How it works | Cloud Run compatible |
|------|-------------|---------------------|
| **Socket Mode** (default) | Gateway connects OUT to Slack via WebSocket. No inbound URL needed. | ✅ Yes — works out of the box |
| **HTTP Events API** | Slack POSTs events to a public URL. Needs inbound webhook. | ✅ Yes — proxy endpoints built into `server.py` |

**Socket Mode setup (add to `secrets.json` → re-encrypt):**

```json
{
  "slack_app_token": "xapp-...",
  "slack_bot_token": "xoxb-...",
  "slack_signing_secret": "..."
}
```

The entrypoint exports these as `SLACK_APP_TOKEN` / `SLACK_BOT_TOKEN` env vars.
OpenClaw reads them automatically — no `openclaw.json` changes needed.

**Slack App configuration (Socket Mode):**
1. Create Slack App at api.slack.com
2. Enable Socket Mode → generate App Token (`xapp-...`, scope: `connections:write`)
3. Install app → copy Bot Token (`xoxb-...`)
4. Subscribe bot events: `app_mention`, `message.im`, `message.channels`, `message.groups`
5. Enable App Home → Messages Tab

**HTTP Events API mode (fallback):**
Set `channels.slack.mode = "http"` in `openclaw.json` and point these Slack URLs
to your Cloud Run service:
- Event Subscriptions: `https://SERVICE_URL/slack/events`
- Interactivity: `https://SERVICE_URL/slack/interactivity`
- Slash Commands: `https://SERVICE_URL/slack/commands`

`server.py` proxies all three paths to the internal gateway at `localhost:3000`.
Requests are verified with HMAC-SHA256 using `SLACK_SIGNING_SECRET`.

### Adding other channels

Same pattern for any OpenClaw channel — add tokens to `secrets.json`, re-encrypt,
add export block to `docker-entrypoint.sh`. Channels that use Socket/WebSocket
(Slack, Discord) work without proxy changes. HTTP-only channels need a proxy
endpoint added to `server.py` following the `_slack_proxy` pattern.

### Local development

```bash
# 1. Copy and fill env
cp .env.example .env
# edit .env: set WORKSPACE_REPO, GITHUB_TOKEN, ENCRYPTION_KEY

# 2. Build and run locally
docker build -f a2a/Dockerfile.a2a -t agentbox-a2a:local .
docker run --env-file .env -p 8080:8080 agentbox-a2a:local

# 3. Test health
curl http://localhost:8080/health

# 4. Deploy to Cloud Run
gcloud run services replace a2a/cloud_run/service.yaml --region=us-central1
```
