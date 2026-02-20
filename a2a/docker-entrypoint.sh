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
SECRETS_ENC_FILE="secrets_encrypted.enc"
SECRETS_JSON="/agentbox/secrets_decrypted.json"

log() { echo "[entrypoint] $*"; }

# ── 1. Validate required env vars ────────────────────────────────────────────
: "${WORKSPACE_REPO:?WORKSPACE_REPO must be set (e.g. owner/repo-name)}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set (from Secret Manager)}"
: "${ENCRYPTION_KEY:?ENCRYPTION_KEY must be set (from Secret Manager)}"

log "Workspace repo: ${WORKSPACE_REPO}"

# ── 2. Auth gh CLI + configure git ───────────────────────────────────────────
echo "${GITHUB_TOKEN}" | gh auth login --with-token
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
get_secret() { jq -r --arg k "$1" '.[$k] // empty' "${SECRETS_JSON}"; }

ANTHROPIC_API_KEY=$(get_secret "anthropic_api_key")
OPENCLAW_GATEWAY_TOKEN=$(get_secret "openclaw_gateway_token")

# Export all secrets as env vars for skills (openclaw picks these up)
# Add new skills here — they just need their key added to secrets.json + re-encrypt
export SMTP_HOST=$(get_secret "smtp_host")
export SMTP_PORT=$(get_secret "smtp_port")
export SMTP_USER=$(get_secret "smtp_user")
export SMTP_PASSWORD=$(get_secret "smtp_password")
export SMTP_FROM=$(get_secret "smtp_from")
export NOTION_SECRET=$(get_secret "notion_secret")
export TELEGRAM_BOT_TOKEN=$(get_secret "telegram_bot_token")

# ── Slack channel (Socket Mode — default) ────────────────────────────────────
# OpenClaw reads SLACK_APP_TOKEN + SLACK_BOT_TOKEN env vars automatically.
# Socket Mode: gateway connects OUT to Slack via WebSocket — no inbound webhook needed.
# HTTP mode: set channels.slack.mode=http in openclaw.json + configure /slack/events URL.
SLACK_APP_TOKEN=$(get_secret "slack_app_token")
SLACK_BOT_TOKEN=$(get_secret "slack_bot_token")
SLACK_SIGNING_SECRET=$(get_secret "slack_signing_secret")

if [ -n "${SLACK_APP_TOKEN}" ] && [ -n "${SLACK_BOT_TOKEN}" ]; then
  export SLACK_APP_TOKEN SLACK_BOT_TOKEN
  [ -n "${SLACK_SIGNING_SECRET}" ] && export SLACK_SIGNING_SECRET
  log "Slack configured (Socket Mode — tokens exported)"
else
  log "Slack tokens not found in secrets bundle — Slack channel disabled"
fi

# Any additional skill secrets are exported dynamically
# (all keys not in the reserved list are exported as-is)
RESERVED_KEYS='["anthropic_api_key","openclaw_gateway_token","smtp_host","smtp_port","smtp_user","smtp_password","smtp_from","notion_secret","telegram_bot_token"]'
while IFS="=" read -r key value; do
  export "${key}=${value}"
done < <(jq -r --argjson reserved "${RESERVED_KEYS}" \
  'to_entries | map(select(.key as $k | $reserved | index($k) | not)) | .[] | "\(.key | ascii_upcase)=\(.value)"' \
  "${SECRETS_JSON}")

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
