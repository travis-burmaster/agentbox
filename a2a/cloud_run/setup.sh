#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-agentbox-a2a}"
A2A_SA="agentbox-a2a@${PROJECT_ID}.iam.gserviceaccount.com"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "PROJECT_ID is required (set env or run: gcloud config set project YOUR_PROJECT_ID)" >&2
  exit 1
fi

echo "Using PROJECT_ID=${PROJECT_ID}, REGION=${REGION}"

echo "[1/6] Enabling required APIs"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com

echo "[2/6] Creating service account ${A2A_SA} (if missing)"
if ! gcloud iam service-accounts describe "${A2A_SA}" >/dev/null 2>&1; then
  gcloud iam service-accounts create agentbox-a2a \
    --display-name="AgentBox A2A Cloud Run Service Account"
fi

cat <<'INFO'
[3/6] Determine Gemini Enterprise caller service account
- In Gemini Enterprise Admin UI / Agent configuration, find the runtime caller identity.
- Or inspect IAM audit logs for failed invocations to this service and capture principalEmail.
- Set GEMINI_CALLER_SA before continuing, e.g.:
    export GEMINI_CALLER_SA="gemini-enterprise-caller@YOUR_PROJECT_ID.iam.gserviceaccount.com"
INFO

if [[ -z "${GEMINI_CALLER_SA:-}" ]]; then
  echo "GEMINI_CALLER_SA is not set; skipping IAM binding and stopping for safety." >&2
  echo "Set GEMINI_CALLER_SA and re-run this script." >&2
  exit 1
fi

echo "[4/6] Running initial Cloud Build + deploy"
gcloud builds submit --config a2a/cloud_run/cloudbuild.yaml .

SERVICE_URL="$(gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" --format='value(status.url)')"

echo "[5/6] Granting Cloud Run Invoker to ${GEMINI_CALLER_SA}"
gcloud run services add-iam-policy-binding "${SERVICE_NAME}" \
  --member="serviceAccount:${GEMINI_CALLER_SA}" \
  --role="roles/run.invoker" \
  --region="${REGION}"

echo "[6/6] Gemini Enterprise registration example (Admin API)"
cat <<EOF
curl -X POST "https://geminienterprise.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/agents" \
  -H "Authorization: Bearer \\$(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "AgentBox",
    "description": "AgentBox A2A sub-agent",
    "a2aConfig": {
      "endpoint": "'"${SERVICE_URL}"'",
      "agentCardUrl": "'"${SERVICE_URL}"'/.well-known/agent.json"
    }
  }'
EOF

cat <<EOF
Next step:
- Update Cloud Run env EXPECTED_CALLER_SA=${GEMINI_CALLER_SA}
- Update EXPECTED_AUDIENCE=${SERVICE_URL}
- Re-deploy if needed:
    gcloud run services update ${SERVICE_NAME} --region ${REGION} \\
      --update-env-vars EXPECTED_CALLER_SA=${GEMINI_CALLER_SA},EXPECTED_AUDIENCE=${SERVICE_URL}
EOF
