#!/bin/bash
# Decrypt secrets_encrypted.enc → secrets.json (local dev only)
# Usage: ./scripts/decrypt-secrets.sh [path/to/secrets_encrypted.enc]
#
# WARNING: secrets.json is gitignored. Never commit it.

set -euo pipefail

INPUT="${1:-secrets_encrypted.enc}"
OUTPUT="secrets.json"

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: ${INPUT} not found"
  exit 1
fi

if [ -z "${ENCRYPTION_KEY:-}" ]; then
  read -rsp "Encryption key: " ENCRYPTION_KEY
  echo
fi

openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 100000 \
  -pass pass:"${ENCRYPTION_KEY}" \
  -in "${INPUT}" \
  -out "${OUTPUT}"

chmod 600 "${OUTPUT}"
echo "✓ Decrypted to ${OUTPUT} (gitignored — do not commit)"
