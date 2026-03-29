#!/bin/bash
# In-container backup script — writes timestamped zip to /agentbox/backups/
# Called by backup-cron supervisord process every BACKUP_INTERVAL_HOURS hours
# Also callable manually: docker exec agentbox-llm /agentbox/bin/backup.sh

set -e

BACKUP_DIR=/agentbox/backups
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ZIPFILE="$BACKUP_DIR/agentbox-backup-$TIMESTAMP.zip"
TMPDIR=$(mktemp -d)

echo "[backup] Starting backup at $TIMESTAMP"

# openclaw state — everything EXCEPT workspace (backed up separately)
echo "[backup] Archiving .openclaw/ (excluding workspace/)..."
tar czf "$TMPDIR/openclaw.tar.gz" \
    --exclude=./workspace \
    -C /agentbox/.openclaw \
    . 2>/dev/null || true

# workspace — separate so restore can be selective
echo "[backup] Archiving workspace/..."
tar czf "$TMPDIR/workspace.tar.gz" \
    -C /agentbox/.openclaw/workspace \
    . 2>/dev/null || true

# agent data
echo "[backup] Archiving data/..."
tar czf "$TMPDIR/data.tar.gz" \
    -C /agentbox/data \
    . 2>/dev/null || true

# Bundle into zip
echo "[backup] Writing $ZIPFILE..."
cd "$TMPDIR"
zip -q "$ZIPFILE" openclaw.tar.gz workspace.tar.gz data.tar.gz
rm -rf "$TMPDIR"

echo "[backup] Created: $ZIPFILE ($(du -sh "$ZIPFILE" | cut -f1))"

# Prune old backups — keep last BACKUP_KEEP_COUNT
KEEP="${BACKUP_KEEP_COUNT:-10}"
EXCESS=$(ls -t "$BACKUP_DIR"/agentbox-backup-*.zip 2>/dev/null | tail -n +$((KEEP + 1)))
if [ -n "$EXCESS" ]; then
    echo "[backup] Pruning old backups (keeping last $KEEP)..."
    echo "$EXCESS" | xargs rm -f
fi

echo "[backup] Done"
