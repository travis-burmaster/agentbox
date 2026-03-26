# Bootstrap Hook

Executed automatically on container startup, **after** memory sync from Turso.

## Steps

1. **Read `memory/runtime/context.md`** — restore current working context and active tasks
2. **Read `memory/runtime/key-decisions.md`** — recall significant decisions already made
3. **Check `memory/runtime/dailylog.md`** — review yesterday's and today's activity
4. **Apply any pending tasks** listed in `context.md` under `## Pending` or `## TODO`

## Memory Hierarchy

After pulling from Turso, you have access to:

| Layer | Where | What |
|-------|-------|------|
| Vector memory | `~/.openclaw/memory/main.sqlite` | File index, semantic chunks, embeddings |
| Flat context | `memory/runtime/context.md` | Active working context (human-readable) |
| Daily log | `memory/runtime/dailylog.md` | Rolling activity log |
| Decisions | `memory/runtime/key-decisions.md` | Important decisions and rationale |
| Long-term | `MEMORY.md` (if in workspace repo) | Curated long-term memory |

## Notes

- Memory is pulled from Turso **before** this hook runs — it's always fresh
- If no Turso vars are set, memory comes from the Docker volume (agentbox-config)
- Flat files in `memory/runtime/` are human-readable and git-committable
