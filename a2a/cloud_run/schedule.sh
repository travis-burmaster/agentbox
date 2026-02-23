#!/usr/bin/env bash
# Create Cloud Scheduler jobs to scale AgentBox Cloud Run to 0 during off-hours.
#
# Schedule (America/New_York):
#   Mon-Fri 05:00  → minScale=1  (wake up for business hours)
#   Mon-Fri 21:00  → minScale=0  (sleep after hours; Fri 21:00 covers the weekend)
#
# Prerequisites:
#   - Cloud Scheduler API enabled
#   - A service account with roles/run.admin on the Cloud Run service
#
# Usage:
#   ./schedule.sh                    # create jobs
#   ./schedule.sh --delete           # remove jobs
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-agentbox-a2a}"
SCHEDULER_LOCATION="${SCHEDULER_LOCATION:-${REGION}}"
TIMEZONE="America/New_York"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "PROJECT_ID is required" >&2; exit 1
fi

# Service account for Cloud Scheduler to call the Cloud Run Admin API.
# Defaults to the same SA used by the Cloud Run service itself, but you
# can set SCHEDULER_SA to a dedicated SA if preferred.
SCHEDULER_SA="${SCHEDULER_SA:-agentbox-a2a@${PROJECT_ID}.iam.gserviceaccount.com}"

CLOUD_RUN_API="https://run.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/services/${SERVICE_NAME}"
UPDATE_MASK="?updateMask=template.scaling.minInstanceCount"

# ── Delete mode ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--delete" ]]; then
  echo "Deleting scheduler jobs..."
  gcloud scheduler jobs delete agentbox-scale-up \
    --location="${SCHEDULER_LOCATION}" --quiet 2>/dev/null || true
  gcloud scheduler jobs delete agentbox-scale-down \
    --location="${SCHEDULER_LOCATION}" --quiet 2>/dev/null || true
  echo "Done — scheduler jobs removed."
  exit 0
fi

# ── Enable APIs ──────────────────────────────────────────────────────────────
echo "[1/4] Enabling Cloud Scheduler API"
gcloud services enable cloudscheduler.googleapis.com --project="${PROJECT_ID}"

# ── Grant run.admin to scheduler SA ──────────────────────────────────────────
echo "[2/4] Granting roles/run.admin to ${SCHEDULER_SA}"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SCHEDULER_SA}" \
  --role="roles/run.admin" \
  --condition=None \
  --quiet

# ── Create / update scale-up job (Mon-Fri 5am ET) ───────────────────────────
echo "[3/4] Creating scale-up job (Mon-Fri 05:00 ${TIMEZONE})"
if gcloud scheduler jobs describe agentbox-scale-up \
     --location="${SCHEDULER_LOCATION}" &>/dev/null; then
  gcloud scheduler jobs update http agentbox-scale-up \
    --location="${SCHEDULER_LOCATION}" \
    --schedule="0 5 * * 1-5" \
    --time-zone="${TIMEZONE}" \
    --uri="${CLOUD_RUN_API}${UPDATE_MASK}" \
    --http-method=PATCH \
    --headers="Content-Type=application/json" \
    --message-body='{"template":{"scaling":{"minInstanceCount":1}}}' \
    --oauth-service-account-email="${SCHEDULER_SA}" \
    --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform"
else
  gcloud scheduler jobs create http agentbox-scale-up \
    --location="${SCHEDULER_LOCATION}" \
    --schedule="0 5 * * 1-5" \
    --time-zone="${TIMEZONE}" \
    --uri="${CLOUD_RUN_API}${UPDATE_MASK}" \
    --http-method=PATCH \
    --headers="Content-Type=application/json" \
    --message-body='{"template":{"scaling":{"minInstanceCount":1}}}' \
    --oauth-service-account-email="${SCHEDULER_SA}" \
    --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform"
fi

# ── Create / update scale-down job (Mon-Fri 9pm ET) ─────────────────────────
echo "[4/4] Creating scale-down job (Mon-Fri 21:00 ${TIMEZONE})"
if gcloud scheduler jobs describe agentbox-scale-down \
     --location="${SCHEDULER_LOCATION}" &>/dev/null; then
  gcloud scheduler jobs update http agentbox-scale-down \
    --location="${SCHEDULER_LOCATION}" \
    --schedule="0 21 * * 1-5" \
    --time-zone="${TIMEZONE}" \
    --uri="${CLOUD_RUN_API}${UPDATE_MASK}" \
    --http-method=PATCH \
    --headers="Content-Type=application/json" \
    --message-body='{"template":{"scaling":{"minInstanceCount":0}}}' \
    --oauth-service-account-email="${SCHEDULER_SA}" \
    --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform"
else
  gcloud scheduler jobs create http agentbox-scale-down \
    --location="${SCHEDULER_LOCATION}" \
    --schedule="0 21 * * 1-5" \
    --time-zone="${TIMEZONE}" \
    --uri="${CLOUD_RUN_API}${UPDATE_MASK}" \
    --http-method=PATCH \
    --headers="Content-Type=application/json" \
    --message-body='{"template":{"scaling":{"minInstanceCount":0}}}' \
    --oauth-service-account-email="${SCHEDULER_SA}" \
    --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform"
fi

echo ""
echo "Schedule active (${TIMEZONE}):"
echo "  Mon-Fri 05:00  → minScale=1  (business hours)"
echo "  Mon-Fri 21:00  → minScale=0  (off-hours + weekends)"
echo ""
echo "To test immediately:"
echo "  gcloud scheduler jobs run agentbox-scale-down --location=${SCHEDULER_LOCATION}"
echo "  gcloud scheduler jobs run agentbox-scale-up   --location=${SCHEDULER_LOCATION}"
echo ""
echo "To remove:"
echo "  $0 --delete"
