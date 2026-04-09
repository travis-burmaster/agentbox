# AgentBox + Local Ollama + Web Search

A minimal AgentBox example that runs the agent runtime in Docker, uses your **local Ollama** as the LLM backend (no cloud, no API keys, no proxy), and enables openclaw's **built-in web search tool** via DuckDuckGo.

Everything runs on your machine. No Anthropic OAuth, no Claude proxy, no cloud LLM bills.

## What you get

- `openclaw-gateway` running in a hardened container on `:3000`
- Talks to **host Ollama** at `host.docker.internal:11434`
- Default model: `qwen3-32k:14b` (a 32K-context variant of qwen3:14b — see [Why not gemma4?](#why-not-gemma4) below)
- Web search powered by openclaw's native `web_search` tool with the **DuckDuckGo** provider (zero-config, no API key)
- `web_fetch` tool for retrieving and reading specific URLs

## Verified end-to-end (qwen3:14b on a 24 GB M4 Mac)

```text
$ docker exec agentbox-ollama openclaw agent --agent main --session-id demo \
    --message "Use the web_search tool to find the current Node.js LTS version. \
               Reply with: the version number, the source URL, and a one-sentence summary."

The current Node.js LTS version is **24.11.0** ("Krypton"), supported until April 2028.
Source URL: https://nodejs.org/en/blog/release/v24.11.0
Summary: This LTS release includes security updates, performance improvements,
and long-term support through 2028.
```

Also verified earlier with `qwen2.5:7b` on the same hardware — both work end-to-end. qwen3:14b gives noticeably more concise / better-formatted answers.

## Prerequisites

1. **Docker** + **Docker Compose** (v2)
2. **Ollama running on the host**. Default model used by this example:
   ```bash
   ollama pull qwen3:14b
   ollama serve            # or rely on the Ollama desktop app
   ```
3. **A 32K-context Modelfile variant.** Ollama defaults to `num_ctx=8192` regardless of what openclaw asks for, and openclaw refuses any model below 16K context. Create a 32K variant with:
   ```bash
   cat > Qwen3-32k.Modelfile <<'EOF'
   FROM qwen3:14b
   PARAMETER num_ctx 32768
   EOF
   ollama create qwen3-32k:14b -f Qwen3-32k.Modelfile
   ```

   On a 24 GB Apple Silicon Mac (M1/M2/M3/M4), `qwen3:14b` is the largest **dense** qwen3 model that fits comfortably alongside Docker and macOS — about 12 GB resident at 32 K context. The 30B-A3B MoE variant is technically smaller in active params but its 19 GB on-disk weight pushes total memory pressure past 24 GB.
   (This bakes a higher num_ctx into the model definition. The underlying weights are unchanged — Ollama just loads them with a bigger KV cache.)
4. **The base `agentbox:latest` Docker image.** Build it once from the repo root:
   ```bash
   git clone https://github.com/travis-burmaster/agentbox.git
   cd agentbox
   docker build --build-arg OPENCLAW_VERSION=2026.3.24 -t agentbox:latest .
   ```
   (Pin to 2026.3.24 or later — earlier versions don't have the `tools.web.search` config schema.)

## Quick Start

```bash
cd agentbox/examples/ollama-websearch

# 1. (optional) generate a gateway token — leave blank for local-only use
cp secrets/secrets.env.template secrets/secrets.env

# 2. start
docker compose up -d

# 3. confirm the model is registered
docker exec agentbox-ollama openclaw models list
# → ollama/qwen3-32k:14b   text   32k   no   yes   default

# 4. talk to the agent (use a unique --session-id, see Gotchas below)
docker exec -it agentbox-ollama openclaw agent --agent main --session-id demo1 \
  --message "Use web_search to find today's top Hacker News story and summarize it."
```

You can also open the gateway UI at <http://localhost:3000>.

## Architecture

```
┌──────────── host (your Mac/Linux) ───────────┐
│                                               │
│   ollama (local)  ─── :11434 ───┐             │
│   model: qwen3-32k:14b          │             │
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

The container reaches host Ollama via Docker's `host.docker.internal` gateway. No proxy, no facade — openclaw speaks the Ollama API natively.

## How web search is wired

Web search is **built into openclaw** — there's no separate skill to install. It's enabled in `config/openclaw.json` under `tools.web.search`:

```json
"tools": {
  "web": {
    "search": {
      "enabled": true,
      "provider": "duckduckgo",
      "maxResults": 5,
      "timeoutSeconds": 30,
      "cacheTtlMinutes": 15
    },
    "fetch": {
      "enabled": true,
      "timeoutSeconds": 30
    }
  }
}
```

DuckDuckGo requires no API key. To swap providers, change `provider` and add credentials to `secrets/secrets.env`:

| Provider     | `provider` value | Env var(s)              |
|--------------|------------------|--------------------------|
| DuckDuckGo   | `duckduckgo`     | *(none — default)*       |
| Brave        | `brave`          | `BRAVE_API_KEY`          |
| Tavily       | `tavily`         | `TAVILY_API_KEY`         |
| Exa          | `exa`            | `EXA_API_KEY`            |
| Perplexity   | `perplexity`     | `PERPLEXITY_API_KEY`     |
| SearXNG      | `searxng`        | `SEARXNG_BASE_URL`       |
| Ollama       | `ollama`         | *(uses local Ollama)*    |

See <https://docs.openclaw.ai/tools/web> for the full provider list.

## Why not gemma4?

The original goal was to use `gemma4:latest`. We ran the test end-to-end and hit two problems:

1. **Gemma family is weak at structured tool calls.** Even given a clear system prompt with `web_search` registered, gemma4-8B kept hallucinating refusals ("I need a Gemini API key…") instead of emitting a tool call.
2. **Inference latency under openclaw's full system prompt + tool schemas + skills index times out.** A simple `"Reply: pong"` round-trip with gemma4 32K-ctx exceeded the 4-minute agent timeout on Apple Silicon. Direct Ollama prompts complete in 4–5 seconds, so the bottleneck is prefill cost on the larger system context.

Qwen2.5:7B avoids both issues — it's strong at tool calls and fast enough that web-search round-trips complete in 1–2 minutes on the same hardware. If you want to try gemma4 anyway, swap the model id in `config/openclaw.json` and increase `--timeout`.

## Gotchas (real bugs we hit while validating this)

1. **Don't bind-mount `openclaw.json` as a single file** — openclaw atomically rewrites it on save and the rename fails with `EBUSY` against a single-file bind mount. The compose file mounts the whole `./config` dir at `/agentbox/host-config:ro` and the `entrypoint` override copies `openclaw.json` into place on each boot. Edits on the host take effect on `docker compose restart`.

2. **openclaw enforces a 16K minimum context window.** Below that, the gateway rejects the model with `Model context window too small (8192 tokens). Minimum is 16000.` and the agent never runs.

3. **Ollama defaults to `num_ctx=8192` no matter what openclaw says.** openclaw's `contextWindow` field in the model spec is *advisory* — the actual context comes from how Ollama loaded the model. You must create a Modelfile variant with `PARAMETER num_ctx 32768` (see Prerequisites) to get a 32K context.

4. **Always pass `--session-id`.** openclaw reuses the default session across CLI calls. If a previous turn errored or said something weird, the next turn will be biased by that history. Pass a fresh `--session-id` per test.

## Volume Map

| Host Path                | Container Path                                  | Purpose                |
|--------------------------|-------------------------------------------------|------------------------|
| `./config/`              | `/agentbox/host-config` (ro)                    | source of openclaw.json |
| `./workspace/`           | `/agentbox/.openclaw/workspace`                 | agent scratch space    |
| `./secrets/secrets.env`  | `/agentbox/secrets/secrets.env` (ro)            | optional credentials   |

## Try more

```bash
# confirm tools are exposed
docker exec agentbox-ollama openclaw agent --agent main --session-id introspect \
  --message "List the tools available to you."
# → web_search, web_fetch, memory_get, memory_search, message, sessions_send, ...

# news summary
docker exec -it agentbox-ollama openclaw agent --agent main --session-id news \
  --message "Search the web for the top story on Hacker News right now and give me a 2-sentence summary with the URL."

# fact lookup with citation
docker exec -it agentbox-ollama openclaw agent --agent main --session-id facts \
  --message "What's the current US 10-year Treasury yield? Search the web and cite the source."

# interactive TUI
docker exec -it agentbox-ollama openclaw tui
```

## Configuration without rebuild

Edit `config/openclaw.json`, then:
```bash
docker compose restart
```
No rebuild needed — the file is mounted via `./config:/agentbox/host-config:ro` and re-copied into place on each container start.

## Troubleshooting

**`connection refused` to Ollama**
The container can't reach `host.docker.internal:11434`. Verify from inside:
```bash
docker exec agentbox-ollama curl -s http://host.docker.internal:11434/api/tags
```
On Linux this only works because of `extra_hosts: host.docker.internal:host-gateway` in the compose file (Docker 20.10+).

**`Model context window too small`**
You're using a model variant that loads with default `num_ctx=8192`. Build a 32K variant via `ollama create … -f Modelfile` (see Prerequisites step 3) and reference its tag in `config/openclaw.json`.

**Model never calls the tool, hallucinates an API key error**
You're probably on a small/weak model (gemma4, llama3.2:1b, qwen2.5:1.5b). Switch to qwen3:14b or larger, or llama3.1:8b. Verify by asking the agent `"List the tools available to you"` in a fresh `--session-id` — it should mention `web_search` and `web_fetch`.

**"This operation was aborted"**
Agent timeout. Either the model is too slow on your hardware or the prompt is too large. Bump `--timeout 600` and check `docker exec agentbox-ollama openclaw logs --plain --limit 50` for the underlying cause.
