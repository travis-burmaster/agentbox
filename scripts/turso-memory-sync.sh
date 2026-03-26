#!/bin/bash
# turso-memory-sync.sh — Sync OpenClaw SQLite memory to/from Turso (libSQL cloud)
#
# Usage:
#   turso-memory-sync.sh init   — Create schema in Turso if not exists
#   turso-memory-sync.sh push   — Export local SQLite → Turso (upsert)
#   turso-memory-sync.sh pull   — Import Turso → local SQLite (on container startup)
#
# Requires: TURSO_URL, TURSO_TOKEN env vars
# Dependencies: bash, curl, python3, sqlite3

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────

TURSO_URL="${TURSO_URL:-}"
TURSO_TOKEN="${TURSO_TOKEN:-}"
LOCAL_DB="${OPENCLAW_HOME:-/agentbox/.openclaw}/memory/main.sqlite"
LOG_PREFIX="[turso-memory]"

# ── Validation ───────────────────────────────────────────────────────────────

if [ -z "$TURSO_URL" ] || [ -z "$TURSO_TOKEN" ]; then
  echo "$LOG_PREFIX ERROR: TURSO_URL and TURSO_TOKEN must be set" >&2
  exit 1
fi

if ! command -v curl &>/dev/null; then
  echo "$LOG_PREFIX ERROR: curl is required" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "$LOG_PREFIX ERROR: python3 is required" >&2
  exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

# Execute SQL against Turso via HTTP pipeline API
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

  # Check for Turso error in response body
  if echo "$body" | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('results',[]); exit(0 if r and r[0].get('type')=='ok' else 1)" 2>/dev/null; then
    echo "$body"
  else
    echo "$LOG_PREFIX ERROR: Turso query failed" >&2
    echo "$LOG_PREFIX Response: $body" >&2
    return 1
  fi
}

# Execute SQL against Turso — batch (array of SQL strings)
turso_exec_batch() {
  local -a sqls=("$@")
  local requests="[]"

  local req_json="[]"
  for sql in "${sqls[@]}"; do
    local json_sql
    json_sql=$(echo "$sql" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")
    req_json=$(echo "$req_json" | python3 -c "
import json, sys
arr = json.load(sys.stdin)
arr.append({'type': 'execute', 'stmt': {'sql': $json_sql}})
print(json.dumps(arr))
")
  done

  local response
  response=$(curl -s -w "\n__HTTP_STATUS__%{http_code}" \
    -X POST "${TURSO_URL}/v2/pipeline" \
    -H "Authorization: Bearer ${TURSO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"requests\": $req_json}")

  local http_status
  http_status=$(echo "$response" | tail -1 | sed 's/__HTTP_STATUS__//')
  local body
  body=$(echo "$response" | head -n -1)

  if [ "$http_status" != "200" ]; then
    echo "$LOG_PREFIX ERROR: Turso batch returned HTTP $http_status" >&2
    echo "$LOG_PREFIX Response: $body" >&2
    return 1
  fi

  echo "$body"
}

# ── Init ─────────────────────────────────────────────────────────────────────

cmd_init() {
  echo "$LOG_PREFIX Initializing Turso schema..."

  # Create tables matching OpenClaw's local SQLite schema
  # See: ~/.openclaw/memory/main.sqlite

  turso_exec "CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT NOT NULL UNIQUE,
    mtime INTEGER NOT NULL,
    size INTEGER NOT NULL,
    hash TEXT NOT NULL,
    indexed_at INTEGER NOT NULL
  )" >/dev/null

  turso_exec "CREATE TABLE IF NOT EXISTS chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    embedding BLOB,
    token_count INTEGER,
    UNIQUE(file_id, chunk_index)
  )" >/dev/null

  turso_exec "CREATE TABLE IF NOT EXISTS embedding_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content_hash TEXT NOT NULL UNIQUE,
    embedding BLOB NOT NULL,
    model TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )" >/dev/null

  # Flat memory table for gitagent-style files
  turso_exec "CREATE TABLE IF NOT EXISTS flat_memory (
    key TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )" >/dev/null

  # Index for performance
  turso_exec "CREATE INDEX IF NOT EXISTS idx_chunks_file_id ON chunks(file_id)" >/dev/null
  turso_exec "CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)" >/dev/null
  turso_exec "CREATE INDEX IF NOT EXISTS idx_embedding_cache_hash ON embedding_cache(content_hash)" >/dev/null

  echo "$LOG_PREFIX Schema initialized ✓"
}

# ── Push ─────────────────────────────────────────────────────────────────────

cmd_push() {
  if [ ! -f "$LOCAL_DB" ]; then
    echo "$LOG_PREFIX No local DB found at $LOCAL_DB — nothing to push"
    return 0
  fi

  echo "$LOG_PREFIX Pushing local SQLite → Turso..."

  # Push files table
  local files_count=0
  while IFS=$'\t' read -r id path mtime size hash indexed_at; do
    local esc_path esc_hash
    esc_path=$(echo "$path" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip('\n')))")
    esc_hash=$(echo "$hash" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip('\n')))")

    turso_exec "INSERT INTO files (id, path, mtime, size, hash, indexed_at)
      VALUES ($id, $esc_path, $mtime, $size, $esc_hash, $indexed_at)
      ON CONFLICT(path) DO UPDATE SET
        mtime=excluded.mtime, size=excluded.size,
        hash=excluded.hash, indexed_at=excluded.indexed_at" >/dev/null

    files_count=$((files_count + 1))
  done < <(sqlite3 "$LOCAL_DB" -separator $'\t' "SELECT id, path, mtime, size, hash, indexed_at FROM files" 2>/dev/null || true)

  echo "$LOG_PREFIX  → $files_count files synced"

  # Push chunks table (content only, skip embeddings for now — they can be re-computed)
  local chunks_count=0
  while IFS=$'\t' read -r id file_id chunk_index content token_count; do
    local esc_content
    esc_content=$(echo "$content" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip('\n')))")

    turso_exec "INSERT INTO chunks (id, file_id, chunk_index, content, token_count)
      VALUES ($id, $file_id, $chunk_index, $esc_content, $token_count)
      ON CONFLICT(file_id, chunk_index) DO UPDATE SET
        content=excluded.content, token_count=excluded.token_count" >/dev/null

    chunks_count=$((chunks_count + 1))
  done < <(sqlite3 "$LOCAL_DB" -separator $'\t' "SELECT id, file_id, chunk_index, content, COALESCE(token_count,0) FROM chunks" 2>/dev/null || true)

  echo "$LOG_PREFIX  → $chunks_count chunks synced"

  # Push embedding_cache
  local emb_count=0
  while IFS=$'\t' read -r id content_hash model created_at; do
    local esc_hash esc_model
    esc_hash=$(echo "$content_hash" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip('\n')))")
    esc_model=$(echo "$model" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip('\n')))")

    # Note: embedding BLOB skipped — re-computed on demand
    turso_exec "INSERT INTO embedding_cache (id, content_hash, embedding, model, created_at)
      VALUES ($id, $esc_hash, X'', $esc_model, $created_at)
      ON CONFLICT(content_hash) DO UPDATE SET
        model=excluded.model, created_at=excluded.created_at" >/dev/null

    emb_count=$((emb_count + 1))
  done < <(sqlite3 "$LOCAL_DB" -separator $'\t' "SELECT id, content_hash, model, created_at FROM embedding_cache" 2>/dev/null || true)

  echo "$LOG_PREFIX  → $emb_count embedding cache entries synced"
  echo "$LOG_PREFIX Push complete ✓"
}

# ── Pull ─────────────────────────────────────────────────────────────────────

cmd_pull() {
  echo "$LOG_PREFIX Pulling Turso → local SQLite..."

  # Ensure local DB directory exists
  local db_dir
  db_dir=$(dirname "$LOCAL_DB")
  mkdir -p "$db_dir"

  # Initialize local SQLite schema if needed
  sqlite3 "$LOCAL_DB" "
    CREATE TABLE IF NOT EXISTS files (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      path TEXT NOT NULL UNIQUE,
      mtime INTEGER NOT NULL,
      size INTEGER NOT NULL,
      hash TEXT NOT NULL,
      indexed_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS chunks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
      chunk_index INTEGER NOT NULL,
      content TEXT NOT NULL,
      embedding BLOB,
      token_count INTEGER,
      UNIQUE(file_id, chunk_index)
    );
    CREATE TABLE IF NOT EXISTS chunks_fts (
      content TEXT
    );
    CREATE TABLE IF NOT EXISTS embedding_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      content_hash TEXT NOT NULL UNIQUE,
      embedding BLOB NOT NULL,
      model TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
  " 2>/dev/null || true

  # Pull files from Turso
  local files_response
  files_response=$(turso_exec "SELECT id, path, mtime, size, hash, indexed_at FROM files")

  echo "$files_response" | python3 - "$LOCAL_DB" <<'PYEOF'
import json, sys, sqlite3

data = json.load(sys.stdin)
db_path = sys.argv[1]

results = data.get("results", [])
if not results or results[0].get("type") != "ok":
    print("[turso-memory] No files data in response", file=sys.stderr)
    sys.exit(0)

rows = results[0].get("response", {}).get("result", {}).get("rows", [])
cols = results[0].get("response", {}).get("result", {}).get("cols", [])

if not rows:
    print("[turso-memory]  → 0 files pulled")
    sys.exit(0)

conn = sqlite3.connect(db_path)
cur = conn.cursor()
count = 0
for row in rows:
    vals = [c.get("value") for c in row]
    cur.execute("""
        INSERT INTO files (id, path, mtime, size, hash, indexed_at)
        VALUES (?,?,?,?,?,?)
        ON CONFLICT(path) DO UPDATE SET
          mtime=excluded.mtime, size=excluded.size,
          hash=excluded.hash, indexed_at=excluded.indexed_at
    """, vals)
    count += 1

conn.commit()
conn.close()
print(f"[turso-memory]  → {count} files pulled")
PYEOF

  # Pull chunks from Turso
  local chunks_response
  chunks_response=$(turso_exec "SELECT id, file_id, chunk_index, content, token_count FROM chunks")

  echo "$chunks_response" | python3 - "$LOCAL_DB" <<'PYEOF'
import json, sys, sqlite3

data = json.load(sys.stdin)
db_path = sys.argv[1]

results = data.get("results", [])
if not results or results[0].get("type") != "ok":
    print("[turso-memory] No chunks data in response", file=sys.stderr)
    sys.exit(0)

rows = results[0].get("response", {}).get("result", {}).get("rows", [])

if not rows:
    print("[turso-memory]  → 0 chunks pulled")
    sys.exit(0)

conn = sqlite3.connect(db_path)
cur = conn.cursor()
count = 0
for row in rows:
    vals = [c.get("value") for c in row]
    cur.execute("""
        INSERT INTO chunks (id, file_id, chunk_index, content, token_count)
        VALUES (?,?,?,?,?)
        ON CONFLICT(file_id, chunk_index) DO UPDATE SET
          content=excluded.content, token_count=excluded.token_count
    """, vals)
    count += 1

conn.commit()
conn.close()
print(f"[turso-memory]  → {count} chunks pulled")
PYEOF

  echo "$LOG_PREFIX Pull complete ✓"
}

# ── Main ─────────────────────────────────────────────────────────────────────

CMD="${1:-}"
case "$CMD" in
  init)   cmd_init ;;
  push)   cmd_push ;;
  pull)   cmd_pull ;;
  *)
    echo "Usage: $0 {init|push|pull}" >&2
    exit 1
    ;;
esac
