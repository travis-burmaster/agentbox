# Teardown Hook

Executed automatically **before** container stops (on SIGTERM/SIGINT).

## Steps

1. **Write session summary to `memory/runtime/dailylog.md`** — append today's key activity
2. **Update `memory/runtime/context.md`** — capture current state, active tasks, next steps
3. **Update `memory/runtime/key-decisions.md`** — record any significant decisions made this session
4. **Push flat-file memory to Turso** — `scripts/memory-sync-gitagent.sh push`
5. **Push SQLite memory to Turso** — `scripts/turso-memory-sync.sh push`
6. **(Optional) Commit and push `memory/` to workspace repo** — for git-based history

## Automatic Teardown

The `docker-entrypoint.sh` registers a SIGTERM trap that automatically runs:
```bash
bash /agentbox/scripts/turso-memory-sync.sh push
bash /agentbox/scripts/memory-sync-gitagent.sh push
```

This happens on `docker stop agentbox` (gives container 10s grace period).

## Agent-Initiated Teardown

The agent can also proactively run teardown before a long idle period:
```bash
bash /agentbox/scripts/memory-sync-gitagent.sh push
bash /agentbox/scripts/turso-memory-sync.sh push
```

## Notes

- Teardown is idempotent — safe to run multiple times
- If Turso is not configured (no TURSO_URL/TURSO_TOKEN), this is a no-op
- Memory in `memory/runtime/` is also preserved in the Docker volume as a fallback
