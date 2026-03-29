# AgentBox + LLM Proxy + GitAgent Example

A self-contained AgentBox deployment powered by `claude_proxy.py` for OAuth → Anthropic access,
with gitagent workspace support and automated in-container backup/restore.

No CLIProxyAPI or external proxy required — just your Claude Max OAuth token.

## Quick Start

```bash
git clone https://github.com/travis-burmaster/agentbox
cd agentbox/examples/llm-proxy-gitagent

# 1. Add your Claude OAuth token
cp secrets/secrets.env.template secrets/secrets.env
# Edit secrets/secrets.env: CLAUDE_OAUTH_TOKEN=your-token

# 2. Optional: seed workspace from your gitagent repo
./export-agent.sh https://github.com/your-org/your-agent

# 3. Start
docker compose up -d

# Agent live at http://localhost:3000
```

## Getting Your Claude OAuth Token

Your token is at `~/.claude/.credentials.json` → `claudeAiOauth.accessToken`.

Or run in your terminal:
```bash
python3 -c "import json; d=json.load(open('$HOME/.claude/.credentials.json')); print(d['claudeAiOauth']['accessToken'])"
```

## Architecture

```
                        ┌─────────────────────────────────────────────────────────┐
                        │                  Docker Container                        │
                        │                                                          │
  Browser / TUI  ──────▶│ :3000  openclaw-gateway  (AI agent runtime)             │
                        │           │                                              │
                        │           │  Ollama API  (/api/chat)                    │
                        │           ▼                                              │
                        │ :11434 ollama-facade     (Ollama-compatible frontend)    │
                        │           │                                              │
                        │           │  OpenAI API  (/v1/chat/completions)          │
                        │           ▼                                              │
                        │ :8319  claude-proxy      (OAuth → Anthropic)            │
                        │           │                                              │
                        │       backup-cron        (every 6h → ./backups/)        │
                        └───────────┼─────────────────────────────────────────────┘
                                    │  HTTPS  Bearer token
                                    ▼
                         api.anthropic.com/v1/messages
                         (claude-sonnet / opus / haiku)
```

**Request flow:** openclaw sends Ollama-format chat → ollama-facade translates to OpenAI format and passes tools through → claude-proxy converts to Anthropic Messages API format, injects OAuth headers, streams the response back up the chain.

Four processes managed by supervisord inside a single container:

| Process | Port | Role |
|---------|------|------|
| `claude-proxy` | 8319 | OAuth → Anthropic API (cloaking headers for sonnet/opus) |
| `ollama-facade` | 11434 | Ollama-compatible frontend for openclaw |
| `openclaw-gateway` | 3000 | AI agent runtime |
| `backup-cron` | — | Periodic backup (default: every 6 hours) |

## Volume Map

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `./config/openclaw.json` | `/agentbox/.openclaw/openclaw.json` (ro) | openclaw config |
| `./config/llm-proxy.yaml` | `/app/config.yaml` (ro) | proxy routing config |
| `./workspace/` | `/agentbox/.openclaw/workspace` | gitagent workspace (editable on host) |
| `./backups/` | `/agentbox/backups` | backup output (readable on host) |
| `./secrets/secrets.env` | `/agentbox/secrets/secrets.env` (ro) | credentials |

## Backup & Restore

```bash
# Manual backup
docker exec agentbox-llm /agentbox/bin/backup.sh

# List backups
./restore.sh list

# Restore latest backup
./restore.sh

# Restore workspace only
./restore.sh --only workspace
```

## GitAgent Workspace

The `./workspace/` directory is bind-mounted into the container. Seed it from your gitagent repo:

```bash
./export-agent.sh https://github.com/your-org/your-agent
docker compose restart
```

After the first seed, persistent state is maintained through backup/restore. The container does NOT re-clone the repo on restart.

## Config Without Rebuild

Edit `config/openclaw.json` or `config/llm-proxy.yaml` and restart:

```bash
docker compose restart
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_OAUTH_TOKEN` | (required) | Claude Max OAuth access token |
| `BACKUP_INTERVAL_HOURS` | `6` | Hours between automatic backups |
| `BACKUP_KEEP_COUNT` | `10` | Max backup zips to retain |

## Proxy Files

The `proxy/` directory contains vendored copies of `claude_proxy.py`, `proxy_core.py`,
and `ollama-facade/server.py` from the [llm-proxy](https://github.com/travis-burmaster/llm-proxy) project.
