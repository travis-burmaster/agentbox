#!/bin/bash
# Encrypt secrets.json → secrets_encrypted.enc
# Usage: ./scripts/encrypt-secrets.sh [path/to/secrets.json]
#
# ENCRYPTION_KEY is read from:
#   1. ENCRYPTION_KEY env var, or
#   2. Prompted interactively
#
# The encrypted file is written to the workspace repo root and should be committed.
# secrets.json is gitignored and should NEVER be committed.

set -euo pipefail

INPUT="${1:-secrets.json}"
OUTPUT="secrets_encrypted.enc"

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: ${INPUT} not found."
  echo "Copy secrets.example.json to secrets.json, fill in values, then re-run."
  exit 1
fi

# Validate JSON
if ! jq empty "${INPUT}" 2>/dev/null; then
  echo "ERROR: ${INPUT} is not valid JSON"
  exit 1
fi

# Get encryption key
if [ -z "${ENCRYPTION_KEY:-}" ]; then
  read -rsp "Encryption key: " ENCRYPTION_KEY
  echo
fi

openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
  -pass pass:"${ENCRYPTION_KEY}" \
  -in "${INPUT}" \
  -out "${OUTPUT}"

echo "✓ Encrypted: ${OUTPUT}"
echo "  Commit ${OUTPUT} to your workspace repo."
echo "  Never commit ${INPUT}."
