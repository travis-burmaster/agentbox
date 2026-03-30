# LLM Proxy Stack

Turns a Claude OAuth token (from a Claude Max subscription) into a local
Ollama-compatible API that OpenClaw can consume. Three components work together
inside the Docker container:

```
OpenClaw gateway (port 3000)
  └─ ollama provider → ollama-facade (port 11434)
                          └─ proxy_core → claude_proxy (port 8319)
                                            └─ api.anthropic.com (OAuth)
```

## Components

### `claude_proxy.py` (port 8319)

Standalone HTTP proxy that authenticates against `api.anthropic.com` using a
Claude OAuth token. Uses `curl-cffi` for Chrome TLS fingerprinting.

**Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/messages` | Anthropic native format (pass-through) |
| `POST` | `/v1/chat/completions` | OpenAI-compatible (auto-converted) |
| `GET` | `/v1/models` | List available models |

**Token resolution order:**

1. OpenClaw auth-profiles (`~/.openclaw/agents/main/agent/auth-profiles.json`)
2. Credentials file (`~/.claude/.credentials.json`) with auto-refresh

### `proxy_core.py`

Shared library used by the ollama facade. Handles failover between primary and
secondary proxy URLs, SQLite call logging, cooldown/backoff, and both streaming
and non-streaming request dispatch via the OpenAI Python SDK.

### `ollama-facade/server.py` (port 11434)

FastAPI server that speaks the Ollama HTTP protocol (`/api/chat`, `/api/tags`,
etc.) so OpenClaw's built-in ollama provider can route to it natively. Translates
Ollama requests into OpenAI-format calls through `proxy_core`.

## Configuration

All routing is configured in `config/llm-proxy.yaml`:

```yaml
primary_url: "http://127.0.0.1:8319/v1"
strategy: "priority"
default_model: "claude-sonnet-4-6"
```

The OpenClaw gateway is configured in `config/openclaw.json` to point its ollama
provider at `http://127.0.0.1:11434`.

## Authentication

The proxy needs a valid `CLAUDE_OAUTH_TOKEN` set in `secrets/secrets.env` (or
passed as an environment variable). Get it from your local Claude credentials:

```bash
cat ~/.claude/.credentials.json | jq -r '.claudeAiOauth.accessToken'
```

If the token has a refresh token, `claude_proxy.py` will auto-refresh it when
it nears expiry.

## Supported Models

The proxy advertises and translates these model names:

- `claude-sonnet-4-6` (default)
- `claude-opus-4-6`
- `claude-haiku-4-5-20251001`

Short aliases like `sonnet`, `opus`, `haiku` are also accepted.
