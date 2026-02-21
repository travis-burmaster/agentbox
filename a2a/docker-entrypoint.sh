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
SECRETS_ENC_FILE=""  # resolved below to latest backup run
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
git config --global user.email "${GIT_AUTHOR_EMAIL:-agentbox@noreply.github.com}"
git config --global user.name "${GIT_AUTHOR_NAME:-AgentBox Cloud Run}"
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
# Resolve the latest backup run (follow backup/latest symlink or find newest run)
if [ -L "${WORKSPACE_DIR}/backup/latest" ] || [ -d "${WORKSPACE_DIR}/backup/latest" ]; then
  # latest may be a symlink with an absolute path from the backup machine — resolve by finding newest run
  LATEST_RUN=$(ls -1d "${WORKSPACE_DIR}"/backup/runs/*/ 2>/dev/null | sort | tail -1)
else
  LATEST_RUN=""
fi

if [ -n "${LATEST_RUN}" ] && [ -f "${LATEST_RUN}/secrets_encrypted.enc" ]; then
  SECRETS_ENC_PATH="${LATEST_RUN}/secrets_encrypted.enc"
  log "Using backup run: $(basename "${LATEST_RUN}")"
elif [ -f "${WORKSPACE_DIR}/backup/secrets_encrypted.enc" ]; then
  SECRETS_ENC_PATH="${WORKSPACE_DIR}/backup/secrets_encrypted.enc"
  log "Using root-level backup/secrets_encrypted.enc"
elif [ -f "${WORKSPACE_DIR}/secrets_encrypted.enc" ]; then
  SECRETS_ENC_PATH="${WORKSPACE_DIR}/secrets_encrypted.enc"
  log "Using workspace root secrets_encrypted.enc"
else
  log "ERROR: secrets_encrypted.enc not found in workspace repo"
  exit 1
fi

log "Decrypting secrets bundle..."
openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 100000 \
  -pass env:ENCRYPTION_KEY \
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

# Look up a key case-insensitively from the env object
get_secret() {
  local val
  val=$(jq -r --arg k "$1" "${ENV_FILTER}"'
    | to_entries[]
    | select(.key | ascii_downcase == ($k | ascii_downcase))
    | .value' "${SECRETS_JSON}" | head -1)
  echo "${val}"
}

ANTHROPIC_API_KEY=$(get_secret "anthropic_api_key")
OPENCLAW_GATEWAY_TOKEN=$(get_secret "openclaw_gateway_token")

# If credentials aren't in the env bundle, try the restored openclaw config
if [ -z "${ANTHROPIC_API_KEY}" ] && [ -f "${OPENCLAW_HOME}/openclaw.json" ]; then
  ANTHROPIC_API_KEY=$(jq -r '.. | .anthropicApiKey? // empty' "${OPENCLAW_HOME}/openclaw.json" 2>/dev/null | head -1)
  log "anthropic_api_key sourced from restored openclaw.json"
fi
if [ -z "${OPENCLAW_GATEWAY_TOKEN}" ] && [ -f "${OPENCLAW_HOME}/openclaw.json" ]; then
  OPENCLAW_GATEWAY_TOKEN=$(jq -r '.. | .gatewayToken? // .token? // empty' "${OPENCLAW_HOME}/openclaw.json" 2>/dev/null | head -1)
  log "openclaw_gateway_token sourced from restored openclaw.json"
fi

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
  # Get the original OPENCLAW_HOME from the backup to rewrite paths
  BACKUP_ROOT=$(jq -r '.openclaw_state.root // empty' "${SECRETS_JSON}")

  log "Restoring openclaw state files..."
  while IFS=$'\t' read -r relpath b64content; do
    dest="${OPENCLAW_HOME}/${relpath}"
    mkdir -p "$(dirname "${dest}")"
    echo "${b64content}" | base64 -d > "${dest}"
    chmod 600 "${dest}"

    # Rewrite hardcoded paths from backup machine to container paths
    if [ -n "${BACKUP_ROOT}" ] && [ "${BACKUP_ROOT}" != "${OPENCLAW_HOME}" ]; then
      BACKUP_HOME=$(dirname "${BACKUP_ROOT}")
      if grep -q "${BACKUP_HOME}" "${dest}" 2>/dev/null; then
        sed -i "s|${BACKUP_ROOT}|${OPENCLAW_HOME}|g" "${dest}"
        sed -i "s|${BACKUP_HOME}|/agentbox|g" "${dest}"
        log "  restored ${relpath} (paths rewritten)"
      else
        log "  restored ${relpath}"
      fi
    else
      log "  restored ${relpath}"
    fi
  done < <(jq -r '.openclaw_state.files | to_entries[] | "\(.key)\t\(.value.content)"' "${SECRETS_JSON}")
fi

# ── 6. Run headless onboard (or skip if config was restored) ─────────────────
# If openclaw.json was restored from the backup and already has a model configured,
# skip onboard entirely — the restored config is the source of truth.
if openclaw config get agents.defaults.model.primary &>/dev/null 2>&1; then
  log "OpenClaw already configured (restored from backup) — skipping onboard"
else
  # Onboard requires credentials
  if [ -z "${ANTHROPIC_API_KEY}" ]; then
    log "ERROR: anthropic_api_key not found in secrets bundle or restored config"
    shred -u "${SECRETS_JSON}" 2>/dev/null || rm -f "${SECRETS_JSON}"
    exit 1
  fi
  if [ -z "${OPENCLAW_GATEWAY_TOKEN}" ]; then
    log "ERROR: openclaw_gateway_token not found in secrets bundle or restored config"
    shred -u "${SECRETS_JSON}" 2>/dev/null || rm -f "${SECRETS_JSON}"
    exit 1
  fi

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
fi

# ── 6b. Ensure Slack DM access is configured ─────────────────────────────────
# If SLACK_ALLOW_FROM is set, configure the Slack DM allowlist.
# Use "*" to allow all users, or comma-separated Slack user IDs.
SLACK_ALLOW_FROM="${SLACK_ALLOW_FROM:-*}"
if command -v openclaw &>/dev/null; then
  openclaw config set channels.slack.dm.enabled true 2>/dev/null || true
  openclaw config set channels.slack.dm.policy open 2>/dev/null || true
  # Set allowFrom as a JSON array (top-level channels.slack.allowFrom per newer schema)
  ALLOW_JSON=$(echo "${SLACK_ALLOW_FROM}" | tr ',' '\n' | jq -R . | jq -s .)
  openclaw config set channels.slack.allowFrom "${ALLOW_JSON}" 2>/dev/null || true
  openclaw config set channels.slack.groupPolicy open 2>/dev/null || true
  # Run doctor --fix to apply any schema migrations
  openclaw doctor --fix 2>/dev/null || true
  log "Slack DM access configured (allowFrom=${SLACK_ALLOW_FROM})"
fi

# ── 6c. Configure Himalaya email skill (SMTP2GO) ─────────────────────────────
SMTP_FROM="${SMTP_FROM:-}"
if [ -n "${SMTP_FROM}" ] && [ -n "${SMTP2GO_USER:-}" ] && [ -n "${SMTP2GO_PASS:-}" ] && command -v himalaya &>/dev/null; then
  HIMALAYA_CONFIG_DIR="/agentbox/.config/himalaya"
  mkdir -p "${HIMALAYA_CONFIG_DIR}"
  MAILDIR_ROOT="/agentbox/.local/share/himalaya/maildir"
  mkdir -p "${MAILDIR_ROOT}/cur" "${MAILDIR_ROOT}/new" "${MAILDIR_ROOT}/tmp"
  mkdir -p "${MAILDIR_ROOT}/Sent/cur" "${MAILDIR_ROOT}/Sent/new" "${MAILDIR_ROOT}/Sent/tmp"

  cat > "${HIMALAYA_CONFIG_DIR}/config.toml" <<TOML
[accounts.default]
email = "${SMTP_FROM}"
display-name = "AgentBox"
default = true

# Local maildir for storing sent copies
backend.type = "maildir"
backend.root = "${MAILDIR_ROOT}"

# SMTP relay via SMTP2GO
message.send.backend.type = "smtp"
message.send.backend.host = "mail.smtp2go.com"
message.send.backend.port = 2525
message.send.backend.encryption.type = "start-tls"
message.send.backend.login = "${SMTP2GO_USER}"
message.send.backend.auth.type = "password"
message.send.backend.auth.cmd = "printenv SMTP2GO_PASS"
TOML
  chmod 600 "${HIMALAYA_CONFIG_DIR}/config.toml"

  # Enable the himalaya skill in openclaw config
  # HIMALAYA_CONFIG is the env var himalaya CLI actually reads for config path
  openclaw config set skills.entries.himalaya.enabled true 2>/dev/null || true
  openclaw config set skills.entries.himalaya.env '{
    "HIMALAYA_CONFIG": "/agentbox/.config/himalaya/config.toml",
    "XDG_CONFIG_HOME": "/agentbox/.config"
  }' 2>/dev/null || true
  log "Himalaya email skill configured (from=${SMTP_FROM}, relay=smtp2go)"
else
  log "SMTP2GO credentials not found or himalaya not installed — email skill skipped"
fi

# ── 7. Shred decrypted secrets (never leave plaintext on disk) ───────────────
shred -u "${SECRETS_JSON}" 2>/dev/null || rm -f "${SECRETS_JSON}"
log "Decrypted secrets file shredded"

log "Boot complete — handing off to supervisord"
exec "$@"
