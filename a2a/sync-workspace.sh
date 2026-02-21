#!/bin/bash
# Periodically commit and push workspace changes (memory, config) to GitHub.
# Runs as a supervisord program with a simple sleep loop.
# On SIGTERM (Cloud Run shutdown), performs a final sync before exit.
set -euo pipefail

WORKSPACE_DIR="/agentbox/.openclaw/workspace"
SYNC_INTERVAL="${WORKSPACE_SYNC_INTERVAL:-60}"  # seconds between checks
LOCK="/tmp/workspace-sync.lock"

log() { echo "[sync-workspace] $*"; }

# ── Final sync on shutdown ────────────────────────────────────────────────────
cleanup() {
  log "SIGTERM received — running final sync before exit"
  do_sync "shutdown"
  exit 0
}
trap cleanup SIGTERM SIGINT

# ── Wait for gateway to be ready (workspace must be cloned) ──────────────────
log "Waiting for workspace to be ready..."
for i in $(seq 1 60); do
  if [ -d "${WORKSPACE_DIR}/.git" ]; then
    break
  fi
  sleep 2
done

if [ ! -d "${WORKSPACE_DIR}/.git" ]; then
  log "ERROR: workspace not found at ${WORKSPACE_DIR} — exiting"
  exit 1
fi

log "Workspace found — starting sync loop (interval=${SYNC_INTERVAL}s)"

# ── Sync function ────────────────────────────────────────────────────────────
do_sync() {
  local reason="${1:-periodic}"

  # Simple file lock to prevent concurrent syncs
  if [ -f "${LOCK}" ]; then
    log "Sync already in progress — skipping (${reason})"
    return 0
  fi
  touch "${LOCK}"

  (
    cd "${WORKSPACE_DIR}"

    # Pull latest first (handle any remote changes)
    git pull --rebase --quiet 2>/dev/null || {
      log "WARNING: pull --rebase failed; attempting merge"
      git pull --no-rebase --quiet 2>/dev/null || true
    }

    # Stage memory files and any other workspace changes
    git add -A 2>/dev/null || true

    # Check if there are staged changes
    if git diff --cached --quiet 2>/dev/null; then
      # No changes to commit
      rm -f "${LOCK}"
      return 0
    fi

    # Build a descriptive commit message
    local changed_files
    changed_files=$(git diff --cached --name-only | head -10)
    local file_count
    file_count=$(git diff --cached --name-only | wc -l | tr -d ' ')

    local msg="agent: auto-sync workspace (${reason}, ${file_count} files)"

    git commit -m "${msg}" --quiet 2>/dev/null || {
      log "WARNING: commit failed"
      rm -f "${LOCK}"
      return 1
    }

    git push --quiet 2>/dev/null || {
      log "WARNING: push failed — will retry next cycle"
      rm -f "${LOCK}"
      return 1
    }

    local sha
    sha=$(git rev-parse --short HEAD)
    log "Synced @ ${sha} (${reason}): ${file_count} file(s) — ${changed_files}"
  )

  rm -f "${LOCK}"
}

# ── Main loop ────────────────────────────────────────────────────────────────
while true; do
  sleep "${SYNC_INTERVAL}" &
  wait $! 2>/dev/null || true   # interruptible sleep (for SIGTERM)
  do_sync "periodic"
done
