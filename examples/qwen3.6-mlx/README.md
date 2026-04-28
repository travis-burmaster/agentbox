# AgentBox + Local Qwen3.6-35B-A3B (MLX)

A minimal AgentBox example that runs the agent runtime in Docker and uses your **local Qwen3.6-35B-A3B** (MoE, ~3B params active per token, MLX 4-bit quantization) as the LLM backend. No cloud, no API keys, no proxy.

Talks to a host-side **`mlx_lm.server`** over the OpenAI-compatible API (`/v1/chat/completions`). Web search via DuckDuckGo (zero-config) is enabled out of the box.

## Why this example

- 100% local inference on Apple Silicon — no Anthropic OAuth, no cloud LLM bills.
- Qwen3.6-35B-A3B is an MoE model: ~35B total params but only ~3B activated per token, so generation is fast (~99 tok/s on M-series with 48 GB unified memory).
- Native context window is 256K; this example advertises 64K to keep KV-cache RAM bounded.

## Architecture

```
┌──────────── host (your Mac) ─────────────────┐
│                                               │
│   mlx_lm.server   ── :8012/v1 ──┐             │
│   model: qwen3.6-35b              │           │
│                                  │             │
│   ┌──── docker container ────────┼─┐          │
│   │                              │ │          │
│   │  openclaw-gateway  :3000 ◀───┘ │          │
│   │      │                          │          │
│   │      ├── tools.web.search ───────────▶ DuckDuckGo (HTTPS)
│   │      └── tools.web.fetch  ───────────▶ arbitrary URLs
│   │                              │ │          │
│   └──────────────────────────────┘ │          │
│                                     │          │
└─────────────────────────────────────┴──────────┘
```

The container reaches the host MLX server via Docker's `host.docker.internal` gateway. openclaw uses its built-in `openai-completions` provider — no shim, no proxy.

## Prerequisites

### 1. Apple Silicon Mac with enough memory

The 4-bit checkpoint is ~22 GB on disk and peaks at ~20 GB resident during inference. **48 GB unified memory recommended** (32 GB will work but you'll see paging on long contexts).

### 2. Python venv with MLX (one-time)

```bash
python3.12 -m venv ~/.venvs/mlx
source ~/.venvs/mlx/bin/activate
pip install -U pip
pip install -U mlx mlx-lm
```

### 3. Pull the prebuilt MLX 4-bit weights (one-time)

The weights are pulled lazily on first server start, but you can pre-fetch:

```bash
~/.venvs/mlx/bin/python -m mlx_lm.generate \
  --model mlx-community/Qwen3.6-35B-A3B-4bit \
  --prompt "Say hello in one sentence." \
  --max-tokens 20
```

This downloads ~22 GB into `~/.cache/huggingface/hub/`.

### 4. Friendly model alias

The openclaw server matches the request `model` field against the loaded model. To send the friendly id `qwen3.6-35b` (and not the long HF repo path), create a local symlink:

```bash
SNAP=$(ls -d ~/.cache/huggingface/hub/models--mlx-community--Qwen3.6-35B-A3B-4bit/snapshots/*/ | head -1)
mkdir -p ~/models
ln -sfn "${SNAP%/}" ~/models/qwen3.6-35b
```

### 5. Start `mlx_lm.server`

Run from `~/models` so the relative `--model qwen3.6-35b` resolves to the symlinked snapshot:

```bash
cd ~/models
~/.venvs/mlx/bin/python -m mlx_lm.server \
  --model qwen3.6-35b \
  --host 0.0.0.0 \
  --port 8012 \
  --chat-template-args '{"enable_thinking": false}' \
  --log-level INFO
```

Notes:
- `--host 0.0.0.0` lets the Docker container reach the server through the host gateway. Use `127.0.0.1` for loopback-only.
- `--chat-template-args '{"enable_thinking": false}'` disables Qwen's `<think>…</think>` reasoning blocks at the chat-template layer — cleaner for tool-calling agents.

Verify the server is healthy:

```bash
curl -sf http://127.0.0.1:8012/health
curl -sS http://127.0.0.1:8012/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.6-35b","max_tokens":16,"messages":[{"role":"user","content":"Reply: pong."}]}'
```

### 6. Build the agentbox base image (one-time)

From the repo root:

```bash
cd ~/git/agentbox
docker build --build-arg OPENCLAW_VERSION=2026.3.24 -t agentbox:latest .
```

Pin to `2026.3.24` or later — earlier versions don't have the `tools.web.search` config schema.

## Quick Start

```bash
cd ~/git/agentbox/examples/qwen3.6-mlx

# (optional) generate a gateway token — leave blank for local-only use
cp secrets/secrets.env.template secrets/secrets.env

docker compose up -d

# confirm the model is registered
docker exec agentbox-qwen openclaw models list
# → qwen-mlx/qwen3.6-35b   text   64k   no   yes   default

# talk to the agent
docker exec -it agentbox-qwen openclaw agent --agent main --session-id smoke \
  --message "Reply with exactly the word PONG."
```

You can also open the gateway UI at <http://localhost:3000>.

## How the LLM is wired

`config/openclaw.json` registers Qwen3.6 as a generic OpenAI-compat provider:

```json
"models": {
  "providers": {
    "qwen-mlx": {
      "baseUrl": "http://host.docker.internal:8012/v1",
      "apiKey": "mlx-local",
      "api": "openai-completions",
      "models": [
        {
          "id": "qwen3.6-35b",
          "name": "Qwen 3.6 35B-A3B (MLX 4-bit, local)",
          "contextWindow": 65536,
          "maxTokens": 4096,
          "input": ["text"]
        }
      ]
    }
  }
}
```

`api: "openai-completions"` is openclaw's generic OpenAI-compatible client (the same path used for Moonshot, Qwen Portal, Venice, etc.). `mlx_lm.server` doesn't validate the API key, but openclaw still sends a `Bearer` header — `"mlx-local"` is a placeholder.

## Try more

```bash
# list tools
docker exec agentbox-qwen openclaw agent --agent main --session-id introspect \
  --message "List the tools available to you."

# web search
docker exec -it agentbox-qwen openclaw agent --agent main --session-id news \
  --message "Use web_search to find the top story on Hacker News and summarize it in 2 sentences with the URL."

# interactive TUI
docker exec -it agentbox-qwen openclaw tui
```

## Configuration without rebuild

Edit `config/openclaw.json`, then:

```bash
docker compose restart
```

No image rebuild needed — `./config` is mounted at `/agentbox/host-config:ro` and the entrypoint copies `openclaw.json` into place on each container start.

## Volume Map

| Host Path                | Container Path                                  | Purpose                |
|--------------------------|-------------------------------------------------|------------------------|
| `./config/`              | `/agentbox/host-config` (ro)                    | source of openclaw.json |
| `./workspace/`           | `/agentbox/.openclaw/workspace`                 | agent scratch space    |
| `./secrets/secrets.env`  | `/agentbox/secrets/secrets.env` (ro)            | optional credentials   |

## Tuning

**More context.** Qwen3.6-35B-A3B's native window is 262 144 tokens (256K). Bump `contextWindow` in `config/openclaw.json` if you want it — but each doubling roughly doubles peak KV-cache RAM. 64K is the safe default on 48 GB Macs.

**Faster prompt prefill.** Pass `--prefill-step-size 4096 --prompt-cache-bytes 4_000_000_000` to `mlx_lm.server` to grow the prefill chunk and reuse KV state across turns.

**Reasoning mode.** Drop `--chat-template-args '{"enable_thinking": false}'` to let Qwen emit `<think>…</think>` blocks. openclaw will pass them through verbatim — most agent loops don't expect this and may misroute the response.

## Troubleshooting

**`connection refused` to mlx_lm.server**
The container can't reach `host.docker.internal:8012`. Verify from inside:
```bash
docker exec agentbox-qwen curl -s http://host.docker.internal:8012/health
```
On Linux this only works because of `extra_hosts: host.docker.internal:host-gateway` in the compose file (Docker 20.10+).

**`Repository Not Found` from the model loader**
The request `model` field must match `--model` passed to the server. If you started the server with `--model mlx-community/Qwen3.6-35B-A3B-4bit`, change `id` in `config/openclaw.json` to that string. The example assumes the friendly `qwen3.6-35b` symlink in step 4.

**`Model context window too small`**
openclaw enforces a 16K minimum. The example advertises 64K so this should never trigger, but if you lowered it: bump `contextWindow` back to ≥ 16384.

**Slow first turn after a restart**
mlx_lm.server holds the model in memory between requests but loses it on restart. First call after restart pays a ~10 s model-load tax.

**"This operation was aborted"**
Agent timeout. Long answers can take a minute or two with a 35B model. Bump `--timeout 600` on `openclaw agent`, or check `docker exec agentbox-qwen openclaw logs --plain --limit 50` for the underlying cause.
