#!/bin/bash
# AgentBox A2A — Cloud Run entrypoint
# Boot sequence:
#   1. Read WORKSPACE_REPO from .env / service.yaml
#   2. Auth gh CLI + git with GITHUB_TOKEN (Secret Manager)
#   3. Clone private workspace repo (workspace files + secrets_encrypted.enc)
#   4. Decrypt secrets bundle with ENCRYPTION_KEY (Secret Manager)
#   5. Run openclaw onboard --non-interactive with decrypted credentials
#   6. Shred decrypted secrets file
#   7. Hand off to supervisord (gateway + A2A)
set -euo pipefail

WORKSPACE_DIR="/agentbox/.openclaw/workspace"
CONFIG_PATH="/agentbox/.openclaw/openclaw.json"
OPENCLAW_HOME="/agentbox/.openclaw"
SECRETS_ENC_FILE="backup/secrets_encrypted.enc"
SECRETS_JSON="/agentbox/secrets_decrypted.json"

log() { echo "[entrypoint] $*"; }

# ── 1. Validate required env vars ────────────────────────────────────────────
: "${WORKSPACE_REPO:?WORKSPACE_REPO must be set (e.g. owner/repo-name)}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set (from Secret Manager)}"
: "${ENCRYPTION_KEY:?ENCRYPTION_KEY must be set (from Secret Manager)}"

log "Workspace repo: ${WORKSPACE_REPO}"

# ── 2. Auth gh CLI + configure git ───────────────────────────────────────────
# gh CLI auto-detects GITHUB_TOKEN env var, so no explicit login needed.
# Configure git for workspace repo push/pull.
git config --global user.email "agentbox@northramp.com"
git config --global user.name "AgentBox Cloud Run"
git config --global credential.helper "store --file /agentbox/.git-credentials"
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > /agentbox/.git-credentials
chmod 600 /agentbox/.git-credentials

# ── 3. Clone or update workspace repo ────────────────────────────────────────
WORKSPACE_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${WORKSPACE_REPO}.git"
mkdir -p "${WORKSPACE_DIR}"

if [ -d "${WORKSPACE_DIR}/.git" ]; then
  log "Workspace exists — pulling latest..."
  git -C "${WORKSPACE_DIR}" pull --ff-only --quiet
else
  log "Cold start — cloning workspace (shallow)..."
  git clone --depth=1 --quiet "${WORKSPACE_URL}" "${WORKSPACE_DIR}"
fi

WORKSPACE_SHA=$(git -C "${WORKSPACE_DIR}" rev-parse --short HEAD)
log "Workspace ready @ ${WORKSPACE_SHA}"

# ── 4. Decrypt secrets bundle ─────────────────────────────────────────────────
SECRETS_ENC_PATH="${WORKSPACE_DIR}/${SECRETS_ENC_FILE}"

if [ ! -f "${SECRETS_ENC_PATH}" ]; then
  log "ERROR: ${SECRETS_ENC_FILE} not found in workspace repo"
  exit 1
fi

log "Decrypting secrets bundle..."
openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 100000 \
  -pass pass:"${ENCRYPTION_KEY}" \
  -in "${SECRETS_ENC_PATH}" \
  -out "${SECRETS_JSON}"
chmod 600 "${SECRETS_JSON}"
log "Secrets decrypted"

# ── 5. Extract credentials from decrypted JSON ───────────────────────────────
# The backup JSON may use either:
#   a) flat layout:   { "anthropic_api_key": "..." }
#   b) nested layout: { "env": { "anthropic_api_key": "..." }, "openclaw_state": {...} }
if jq -e '.env' "${SECRETS_JSON}" >/dev/null 2>&1; then
  ENV_FILTER='.env'
else
  ENV_FILTER='.'
fi

get_secret() { jq -r --arg k "$1" "${ENV_FILTER}"'[$k] // empty' "${SECRETS_JSON}"; }

ANTHROPIC_API_KEY=$(get_secret "anthropic_api_key")
OPENCLAW_GATEWAY_TOKEN=$(get_secret "openclaw_gateway_token")

# Export every key from the env object as an uppercase env var
# (except encryption_key which should not be re-exported)
while IFS="=" read -r key value; do
  [[ -z "${key}" ]] && continue
  export "${key}=${value}"
  log "  exported ${key}"
done < <(jq -r "${ENV_FILTER}"' | to_entries[]
  | select(.key != "encryption_key")
  | select(.value | type == "string")
  | "\(.key | ascii_upcase)=\(.value)"' "${SECRETS_JSON}")

# ── 5b. Restore openclaw state files (auth providers, models, etc.) ──────
# The backup stores base64-encoded files under .openclaw_state.files
# Paths are relative to OPENCLAW_HOME (e.g. agents/<id>/agent/auth.json)
if jq -e '.openclaw_state.files // empty' "${SECRETS_JSON}" >/dev/null 2>&1; then
  log "Restoring openclaw state files..."
  while IFS=$'\t' read -r relpath b64content; do
    dest="${OPENCLAW_HOME}/${relpath}"
    mkdir -p "$(dirname "${dest}")"
    echo "${b64content}" | base64 -d > "${dest}"
    chmod 600 "${dest}"
    log "  restored ${relpath}"
  done < <(jq -r '.openclaw_state.files | to_entries[] | "\(.key)\t\(.value.content)"' "${SECRETS_JSON}")
fi

# ── 6. Run headless onboard ───────────────────────────────────────────────────
if [ -z "${ANTHROPIC_API_KEY}" ]; then
  log "ERROR: anthropic_api_key missing from secrets bundle"
  shred -u "${SECRETS_JSON}" 2>/dev/null || rm -f "${SECRETS_JSON}"
  exit 1
fi

if [ -z "${OPENCLAW_GATEWAY_TOKEN}" ]; then
  log "ERROR: openclaw_gateway_token missing from secrets bundle"
  shred -u "${SECRETS_JSON}" 2>/dev/null || rm -f "${SECRETS_JSON}"
  exit 1
fi

if ! openclaw config get agents.defaults.model.primary &>/dev/null 2>&1; then
  log "Running headless onboard..."
  openclaw onboard \
    --non-interactive --accept-risk \
    --flow manual --mode local \
    --auth-choice anthropic-api-key \
    --anthropic-api-key "${ANTHROPIC_API_KEY}" \
    --gateway-auth token \
    --gateway-token "${OPENCLAW_GATEWAY_TOKEN}" \
    --gateway-bind loopback \
    --workspace "${WORKSPACE_DIR}" \
    --skip-channels --skip-daemon \
    --skip-skills --skip-ui --skip-health \
    --no-install-daemon
  log "Onboard complete"
else
  log "OpenClaw already configured — skipping onboard"
fi

# ── 7. Shred decrypted secrets (never leave plaintext on disk) ───────────────
shred -u "${SECRETS_JSON}" 2>/dev/null || rm -f "${SECRETS_JSON}"
log "Decrypted secrets file shredded"

log "Boot complete — handing off to supervisord"
exec "$@"
