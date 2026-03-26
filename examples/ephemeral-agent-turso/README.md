# Ephemeral Agent with Turso Durable Memory

This example shows how to run an AgentBox container with **zero local persistent storage**, using Turso (libSQL cloud) as the memory backend.

## The Problem

Ephemeral containers lose all memory on restart:
- Docker volumes help, but can't follow the agent across machines or Cloud Run instances
- Memory needs to be durable, queryable, and fast to restore

## The Solution

```
Container starts → pull memory from Turso → run → push memory to Turso → container stops
```

On startup, AgentBox:
1. Pulls the SQLite memory DB (files, chunks, embeddings) from Turso
2. Pulls gitagent flat files (context.md, dailylog.md, key-decisions.md) from Turso
3. Starts normally — the agent has full memory from the previous session

On shutdown (SIGTERM from `docker stop`):
1. Pushes updated SQLite memory to Turso
2. Pushes updated flat files to Turso
3. Container exits cleanly

## Quick Setup (3 Steps)

### Step 1: Create a Turso database

```bash
# Install Turso CLI
curl -sSfL https://get.tur.so/install.sh | bash

# Log in
turso auth login

# Create your agent's database
turso db create my-agent-memory

# Get connection details
turso db show --url my-agent-memory
turso db tokens create my-agent-memory
```

### Step 2: Set environment variables

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export TURSO_URL="libsql://my-agent-memory-yourname.turso.io"
export TURSO_TOKEN="eyJhbGciOiJF..."
```

### Step 3: Spin up

```bash
# From the agentbox repo root, build first:
docker build -t agentbox:latest .

# Then from this example directory:
cd examples/ephemeral-agent-turso
docker compose up
```

That's it. Your agent now has persistent memory across restarts, deployments, and machines.

## Memory Hierarchy

| Layer | Storage | Contents | When synced |
|-------|---------|----------|-------------|
| SQLite memory | Turso → tmpfs | File index, semantic chunks, embedding cache | Startup (pull) / Shutdown (push) |
| Flat context | Turso → disk | `memory/runtime/context.md` | Startup / Shutdown |
| Daily log | Turso → disk | `memory/runtime/dailylog.md` | Startup / Shutdown |
| Key decisions | Turso → disk | `memory/runtime/key-decisions.md` | Startup / Shutdown |
| Long-term | Git repo | `MEMORY.md` | On commit/push |

## What Persists vs. What Resets

**Persists (in Turso):**
- Everything the agent has indexed and learned
- Current working context and active tasks
- Daily activity log
- Significant decisions
- Semantic embeddings (for memory search)

**Resets on container restart:**
- In-flight operations (expected — agent picks up from context.md)
- Any files written to tmpfs but not indexed

## Turso Pricing

- **Free tier:** 500 databases, 8GB storage, 1B row reads/month
- **Agent memory is tiny** — typically <10MB per agent
- You can run hundreds of agents on the free tier

## Extending This Pattern

### Multi-agent memory sharing

Multiple agents can share one Turso DB with different key prefixes:
```sql
-- In flat_memory, use namespaced keys:
-- "agent-1/memory/runtime/context.md"
-- "agent-2/memory/runtime/context.md"
```

### Cloud Run / Kubernetes

This pattern works perfectly with:
- **Google Cloud Run** — containers are ephemeral by design
- **Kubernetes** — pods restart, memory persists in Turso
- **Fly.io machines** — fast spin-up, Turso is globally replicated

### Turso edge replication

Turso supports embedded replicas for ultra-low latency reads:
```bash
turso db replicate my-agent-memory --location cdg  # Paris
turso db replicate my-agent-memory --location nrt  # Tokyo
```

The agent always writes to the primary and reads from the nearest replica.

## See Also

- [Turso docs](https://docs.turso.tech)
- [gitagent project](https://github.com/open-gitagent/gitagent) — inspiration for flat-file memory
- [AgentBox README](../../README.md) — full AgentBox documentation
- [`scripts/turso-memory-sync.sh`](../../scripts/turso-memory-sync.sh) — SQLite sync script
- [`scripts/memory-sync-gitagent.sh`](../../scripts/memory-sync-gitagent.sh) — flat-file sync script
