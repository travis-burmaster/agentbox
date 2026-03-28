# AgentBox + LLM Proxy (Ollama Facade) — Docker Deployment

Run AgentBox powered by **Claude Max via OAuth** — no Anthropic API key required.

Uses `ollama-facade` + `claude_proxy.py` from [travis-burmaster/llm-proxy](https://github.com/travis-burmaster/llm-proxy) to present Claude as a local Ollama-compatible endpoint inside the container.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Docker Container                                            │
│                                                              │
│  ┌────────────────┐   ┌──────────────────┐  ┌─────────────┐ │
│  │ openclaw-      │──▶│  ollama-facade   │─▶│ claude_     │ │
│  │ gateway :3000  │   │  :11434          │  │ proxy :8319 │ │
│  └────────────────┘   └──────────────────┘  └──────┬──────┘ │
│                                                     │        │
└─────────────────────────────────────────────────────┼────────┘
                                                      │ OAuth
                                               api.anthropic.com
```

Three processes run under supervisord:
1. `claude_proxy` — reads your Claude OAuth token, proxies to Anthropic API
2. `ollama-facade` — presents Claude as a local Ollama server
3. `openclaw-gateway` — the AI agent runtime

No CLIProxyAPI install needed. No Anthropic API key needed.

## Prerequisites

- Docker + Docker Compose
- A Claude Max account with an active OAuth token (from `openclaw` or Claude desktop app)

## Quick Start

```bash
cd examples/ollama-llm-proxy

# Copy the secrets template
cp secrets/secrets.env.template secrets/secrets.env

# Add your Claude OAuth token to secrets/secrets.env:
#   CLAUDE_OAUTH_TOKEN=your-token-here
# (Find it in ~/.openclaw/agents/main/agent/auth-profiles.json on your host)

docker compose up -d
```

The agent is live at `http://localhost:3000`.

## Getting Your OAuth Token

```bash
# On your host machine (where openclaw is installed):
cat ~/.openclaw/agents/main/agent/auth-profiles.json | python3 -c "
import sys, json
d = json.load(sys.stdin)
token = d['profiles']['anthropic:default']['token']
print(token[:40] + '...')
"
```

Paste that full token into `secrets/secrets.env` as `CLAUDE_OAUTH_TOKEN`.

## Configuration

### Model selection

Edit `config/openclaw.json` to change the default model:
```json
"primary": "ollama/claude-sonnet-4-6"
```

Available models (must match `config/llm-proxy.yaml`):
- `ollama/claude-sonnet-4-6`
- `ollama/claude-haiku-4-5-20251001`
- `ollama/claude-opus-4-6`

### Adding a second OAuth token for failover

In `secrets/secrets.env`:
```
CLAUDE_OAUTH_TOKEN=primary-token
CLAUDE_OAUTH_TOKEN_1=secondary-token
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Builds image with OpenClaw + ollama-facade + claude_proxy |
| `docker-compose.yml` | Orchestrates the deployment |
| `supervisord.conf` | Manages all 3 processes (startup order matters) |
| `config/openclaw.json` | OpenClaw config — points at local ollama-facade |
| `config/llm-proxy.yaml` | LLM proxy config — models, token settings |
| `secrets/secrets.env.template` | Credential template (copy to `secrets.env`) |

## Troubleshooting

```bash
# Check all service logs
docker compose logs -f

# Test claude_proxy is working
docker exec agentbox-llm curl -s http://localhost:8319/

# Test ollama-facade model list
docker exec agentbox-llm curl -s http://localhost:11434/api/tags | python3 -m json.tool

# Test a full chat round-trip
docker exec agentbox-llm curl -s -X POST http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-6","messages":[{"role":"user","content":"ping"}],"stream":false}'
```
