#!/bin/bash
# memory-sync-gitagent.sh — Sync gitagent-style flat-file memory to/from Turso
#
# Usage:
#   memory-sync-gitagent.sh push   — Upload flat memory files → Turso flat_memory table
#   memory-sync-gitagent.sh pull   — Download Turso flat_memory → flat files on disk
#
# Flat memory files synced:
#   memory/runtime/context.md        — Current active context / working memory
#   memory/runtime/dailylog.md       — Rolling daily log
#   memory/runtime/key-decisions.md  — Significant decisions log
#
# Requires: TURSO_URL, TURSO_TOKEN env vars
# Workspace root: WORKSPACE_DIR (default: /agentbox/.openclaw/workspace)

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────

TURSO_URL="${TURSO_URL:-}"
TURSO_TOKEN="${TURSO_TOKEN:-}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/agentbox/.openclaw/workspace}"
LOG_PREFIX="[gitagent-memory]"

FLAT_FILES=(
  "memory/runtime/context.md"
  "memory/runtime/dailylog.md"
  "memory/runtime/key-decisions.md"
)

# ── Validation ───────────────────────────────────────────────────────────────

if [ -z "$TURSO_URL" ] || [ -z "$TURSO_TOKEN" ]; then
  echo "$LOG_PREFIX ERROR: TURSO_URL and TURSO_TOKEN must be set" >&2
  exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

turso_exec() {
  local sql="$1"
  local json_sql
  json_sql=$(echo "$sql" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")

  local response
  response=$(curl -s -w "\n__HTTP_STATUS__%{http_code}" \
    -X POST "${TURSO_URL}/v2/pipeline" \
    -H "Authorization: Bearer ${TURSO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"requests\": [{\"type\": \"execute\", \"stmt\": {\"sql\": ${json_sql}}}]}")

  local http_status
  http_status=$(echo "$response" | tail -1 | sed 's/__HTTP_STATUS__//')
  local body
  body=$(echo "$response" | head -n -1)

  if [ "$http_status" != "200" ]; then
    echo "$LOG_PREFIX ERROR: Turso returned HTTP $http_status" >&2
    echo "$LOG_PREFIX Response: $body" >&2
    return 1
  fi

  echo "$body"
}

# Ensure flat_memory table exists (idempotent)
ensure_schema() {
  turso_exec "CREATE TABLE IF NOT EXISTS flat_memory (
    key TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )" >/dev/null
}

# ── Push ─────────────────────────────────────────────────────────────────────

cmd_push() {
  echo "$LOG_PREFIX Pushing flat memory files → Turso..."
  ensure_schema

  local now
  now=$(date +%s)
  local pushed=0

  for rel_path in "${FLAT_FILES[@]}"; do
    local full_path="${WORKSPACE_DIR}/${rel_path}"

    if [ ! -f "$full_path" ]; then
      echo "$LOG_PREFIX  ⚠ Skipping $rel_path (not found)"
      continue
    fi

    local content
    content=$(cat "$full_path")

    # Escape key and content as JSON strings for safe SQL embedding
    local esc_key esc_content
    esc_key=$(echo "$rel_path" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip('\n')))")
    esc_content=$(echo "$content" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")

    turso_exec "INSERT INTO flat_memory (key, content, updated_at)
      VALUES ($esc_key, $esc_content, $now)
      ON CONFLICT(key) DO UPDATE SET
        content=excluded.content, updated_at=excluded.updated_at" >/dev/null

    echo "$LOG_PREFIX  → pushed: $rel_path ($(echo "$content" | wc -l) lines)"
    pushed=$((pushed + 1))
  done

  echo "$LOG_PREFIX Push complete ($pushed files) ✓"
}

# ── Pull ─────────────────────────────────────────────────────────────────────

cmd_pull() {
  echo "$LOG_PREFIX Pulling flat memory files ← Turso..."
  ensure_schema

  # Fetch all flat_memory rows in one query
  local response
  response=$(turso_exec "SELECT key, content FROM flat_memory WHERE key IN ($(
    python3 -c "
import json
keys = $(python3 -c "import json; print(json.dumps([
  'memory/runtime/context.md',
  'memory/runtime/dailylog.md',
  'memory/runtime/key-decisions.md'
]))")
print(', '.join(json.dumps(k) for k in keys))
")") || true

  # Parse response and write files
  echo "$response" | python3 - "$WORKSPACE_DIR" <<'PYEOF'
import json, sys, os

data = json.load(sys.stdin)
workspace = sys.argv[1]

results = data.get("results", [])
if not results or results[0].get("type") != "ok":
    print("[gitagent-memory]  → No flat memory in Turso (fresh start)")
    sys.exit(0)

rows = results[0].get("response", {}).get("result", {}).get("rows", [])

if not rows:
    print("[gitagent-memory]  → No flat memory rows found (fresh start)")
    sys.exit(0)

pulled = 0
for row in rows:
    key = row[0].get("value", "")
    content = row[1].get("value", "")

    if not key:
        continue

    full_path = os.path.join(workspace, key)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)

    with open(full_path, "w") as f:
        f.write(content)

    lines = len(content.splitlines())
    print(f"[gitagent-memory]  ← pulled: {key} ({lines} lines)")
    pulled += 1

print(f"[gitagent-memory] Pull complete ({pulled} files) ✓")
PYEOF
}

# ── Main ─────────────────────────────────────────────────────────────────────

CMD="${1:-}"
case "$CMD" in
  push)   cmd_push ;;
  pull)   cmd_pull ;;
  *)
    echo "Usage: $0 {push|pull}" >&2
    exit 1
    ;;
esac
