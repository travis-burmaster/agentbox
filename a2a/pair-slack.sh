#!/bin/bash
# One-shot script: wait for gateway, then approve Slack pairing.
# Runs as a supervisord program with autorestart=false.
set -euo pipefail

PAIRING_CODE="${SLACK_PAIRING_CODE:-}"
if [ -z "${PAIRING_CODE}" ]; then
  echo "[pair-slack] No SLACK_PAIRING_CODE set — skipping"
  exit 0
fi

echo "[pair-slack] Waiting for gateway to be ready..."
for i in $(seq 1 30); do
  if openclaw status &>/dev/null; then
    break
  fi
  sleep 2
done

echo "[pair-slack] Approving Slack pairing code: ${PAIRING_CODE}"
openclaw pairing approve slack "${PAIRING_CODE}" || true
echo "[pair-slack] Done"
