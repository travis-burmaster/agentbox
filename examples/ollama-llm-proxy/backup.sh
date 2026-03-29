#!/bin/bash
# AgentBox — backup persistent storage to a zip file on the host
# Usage:
#   ./backup.sh           — creates agentbox-backup-YYYYMMDD-HHMMSS.zip
#   ./backup.sh restore   — restores from latest backup zip
#   ./backup.sh restore agentbox-backup-20260328-120000.zip

set -e

BACKUP_DIR="$(dirname "$0")/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/agentbox-backup-$TIMESTAMP.zip"

# Named volumes to back up
VOLUMES=(
    "ollama-llm-proxy_agentbox-config:/agentbox/.openclaw"
    "ollama-llm-proxy_agentbox-data:/agentbox/data"
)

# ── Backup ────────────────────────────────────────────────────────────────────
backup() {
    mkdir -p "$BACKUP_DIR"
    echo "📦 AgentBox Backup — $TIMESTAMP"
    echo ""

    TMP_DIR=$(mktemp -d)
    trap "rm -rf $TMP_DIR" EXIT

    for entry in "${VOLUMES[@]}"; do
        VOLUME="${entry%%:*}"
        MOUNT="${entry##*:}"
        NAME=$(basename "$MOUNT")

        echo "  → Copying volume: $VOLUME"
        docker run --rm \
            -v "$VOLUME:$MOUNT:ro" \
            -v "$TMP_DIR:/backup" \
            ubuntu:22.04 \
            bash -c "cd '$MOUNT' && tar czf '/backup/$NAME.tar.gz' . 2>/dev/null || true"
    done

    echo ""
    echo "  → Zipping to $BACKUP_FILE"
    (cd "$TMP_DIR" && zip -q "$BACKUP_FILE" *.tar.gz)

    SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
    echo ""
    echo "✅ Backup complete: $BACKUP_FILE ($SIZE)"
    echo ""
    echo "To restore: ./backup.sh restore $BACKUP_FILE"
}

# ── Restore ───────────────────────────────────────────────────────────────────
restore() {
    local ZIP_FILE="$1"

    # If no file given, use latest
    if [ -z "$ZIP_FILE" ]; then
        ZIP_FILE=$(ls -t "$BACKUP_DIR"/agentbox-backup-*.zip 2>/dev/null | head -1)
        if [ -z "$ZIP_FILE" ]; then
            echo "❌ No backup files found in $BACKUP_DIR"
            exit 1
        fi
    fi

    if [ ! -f "$ZIP_FILE" ]; then
        echo "❌ File not found: $ZIP_FILE"
        exit 1
    fi

    echo "⚠️  This will overwrite existing volume data!"
    echo "   Restoring from: $ZIP_FILE"
    read -rp "   Continue? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    TMP_DIR=$(mktemp -d)
    trap "rm -rf $TMP_DIR" EXIT

    echo ""
    echo "📂 Extracting backup..."
    unzip -q "$ZIP_FILE" -d "$TMP_DIR"

    for entry in "${VOLUMES[@]}"; do
        VOLUME="${entry%%:*}"
        MOUNT="${entry##*:}"
        NAME=$(basename "$MOUNT")
        TAR="$TMP_DIR/$NAME.tar.gz"

        if [ ! -f "$TAR" ]; then
            echo "  ⚠️  Skipping $VOLUME — not found in backup"
            continue
        fi

        echo "  → Restoring volume: $VOLUME"
        docker run --rm \
            -v "$VOLUME:$MOUNT" \
            -v "$TMP_DIR:/backup" \
            ubuntu:22.04 \
            bash -c "rm -rf '$MOUNT'/* '$MOUNT'/.[!.]* 2>/dev/null; tar xzf '/backup/$NAME.tar.gz' -C '$MOUNT'"
    done

    echo ""
    echo "✅ Restore complete. Restart the container:"
    echo "   docker compose restart"
}

# ── Main ──────────────────────────────────────────────────────────────────────
case "${1:-backup}" in
    backup)  backup ;;
    restore) restore "$2" ;;
    list)
        echo "Available backups:"
        ls -lh "$BACKUP_DIR"/agentbox-backup-*.zip 2>/dev/null || echo "  (none)"
        ;;
    *)
        echo "Usage: $0 [backup|restore [file]|list]"
        exit 1
        ;;
esac
