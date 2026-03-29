#!/usr/bin/env bash
# Restore AgentBox from backup zip.
#
# Usage:
#   ./restore.sh                                           # restore from latest backup
#   ./restore.sh backups/agentbox-backup-20260329-120000.zip  # restore specific
#   ./restore.sh --only openclaw                           # restore openclaw only
#   ./restore.sh --only workspace                          # restore workspace only
#   ./restore.sh --only data                               # restore data only
#   ./restore.sh list                                      # list available backups

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# ── Arg parsing ────────────────────────────────────────────────────────────────
ONLY=""
ZIPFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        list)
            echo "Available backups:"
            ls -lht "$BACKUP_DIR"/agentbox-backup-*.zip 2>/dev/null \
                | awk '{print $5, $6, $7, $8, $9}' \
                || echo "  (none found in $BACKUP_DIR)"
            exit 0
            ;;
        --only)
            ONLY="$2"
            shift 2
            ;;
        *)
            ZIPFILE="$1"
            shift
            ;;
    esac
done

# ── Find backup zip ────────────────────────────────────────────────────────────
if [ -z "$ZIPFILE" ]; then
    ZIPFILE=$(ls -t "$BACKUP_DIR"/agentbox-backup-*.zip 2>/dev/null | head -1 || true)
    if [ -z "$ZIPFILE" ]; then
        echo "ERROR: No backup zip found in $BACKUP_DIR"
        exit 1
    fi
    echo "Using latest backup: $ZIPFILE"
fi

if [ ! -f "$ZIPFILE" ]; then
    echo "ERROR: Backup file not found: $ZIPFILE"
    exit 1
fi

echo "Restoring from: $ZIPFILE"
[ -n "$ONLY" ] && echo "Restore scope: $ONLY only"

# ── Stop container ─────────────────────────────────────────────────────────────
echo "Stopping container..."
docker compose -f "$COMPOSE_FILE" stop

# ── Extract zip ────────────────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Extracting backup..."
unzip -q "$ZIPFILE" -d "$TMPDIR"

# ── Restore functions ──────────────────────────────────────────────────────────
restore_volume() {
    local volume_name="$1"
    local tarball="$2"
    local mount_path="$3"

    if [ ! -f "$TMPDIR/$tarball" ]; then
        echo "  WARNING: $tarball not found in backup, skipping"
        return
    fi

    echo "  Restoring $volume_name from $tarball..."
    docker run --rm \
        -v "${volume_name}:${mount_path}" \
        -v "$TMPDIR:/backup:ro" \
        ubuntu \
        sh -c "cd ${mount_path} && tar xzf /backup/${tarball} --overwrite"
}

restore_workspace() {
    if [ ! -f "$TMPDIR/workspace.tar.gz" ]; then
        echo "  WARNING: workspace.tar.gz not found in backup, skipping"
        return
    fi

    echo "  Restoring workspace/ bind-mount..."
    tar xzf "$TMPDIR/workspace.tar.gz" -C "$SCRIPT_DIR/workspace/" --overwrite
}

# ── Run restores ───────────────────────────────────────────────────────────────
# Detect volume names from docker-compose (uses directory prefix)
COMPOSE_DIR=$(basename "$SCRIPT_DIR")
OPENCLAW_VOLUME="${COMPOSE_DIR}_agentbox-config"
DATA_VOLUME="${COMPOSE_DIR}_agentbox-data"

if [ -z "$ONLY" ] || [ "$ONLY" = "openclaw" ]; then
    restore_volume "$OPENCLAW_VOLUME" "openclaw.tar.gz" "/agentbox/.openclaw"
fi

if [ -z "$ONLY" ] || [ "$ONLY" = "workspace" ]; then
    restore_workspace
fi

if [ -z "$ONLY" ] || [ "$ONLY" = "data" ]; then
    restore_volume "$DATA_VOLUME" "data.tar.gz" "/agentbox/data"
fi

# ── Restart ────────────────────────────────────────────────────────────────────
echo "Restarting container..."
docker compose -f "$COMPOSE_FILE" start

echo ""
echo "Restore complete from: $ZIPFILE"
