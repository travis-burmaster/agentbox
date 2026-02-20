#!/bin/bash
# AgentBox A2A — Lightweight entrypoint for Cloud Run
# No age/ufw/auditd — not needed in managed Cloud Run environment.
set -e

AUTH_DIR="/agentbox/.openclaw/agents/main/agent"
mkdir -p "${AUTH_DIR}" /agentbox/.openclaw/workspace /agentbox/data /agentbox/logs

# Inject auth credentials from OPENCLAW_AUTH_PROFILES_JSON env var (set via Secret Manager)
if [ -n "${OPENCLAW_AUTH_PROFILES_JSON}" ]; then
    echo "${OPENCLAW_AUTH_PROFILES_JSON}" > "${AUTH_DIR}/auth-profiles.json"
    echo "Auth profiles injected from environment"
fi

exec "$@"
