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

echo "[1/8] Enabling required APIs"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com

echo "[2/8] Creating service account ${A2A_SA} (if missing)"
if ! gcloud iam service-accounts describe "${A2A_SA}" >/dev/null 2>&1; then
  gcloud iam service-accounts create agentbox-a2a \
    --display-name="AgentBox A2A Cloud Run Service Account"
fi

echo "[3/8] Creating secrets in Secret Manager (if missing)"
for secret_name in agentbox-github-token agentbox-encryption-key; do
  if ! gcloud secrets describe "${secret_name}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "  Creating secret: ${secret_name}"
    gcloud secrets create "${secret_name}" \
      --project="${PROJECT_ID}" \
      --replication-policy=automatic
    echo "  ⚠ Add a version:  echo -n 'VALUE' | gcloud secrets versions add ${secret_name} --data-file=-"
  else
    echo "  Secret ${secret_name} already exists"
  fi
done

echo "[4/8] Granting Secret Manager access to ${A2A_SA}"
for secret_name in agentbox-github-token agentbox-encryption-key; do
  gcloud secrets add-iam-policy-binding "${secret_name}" \
    --project="${PROJECT_ID}" \
    --member="serviceAccount:${A2A_SA}" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet
done

cat <<'INFO'
[5/8] Determine Gemini Enterprise caller service account
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

echo "[6/8] Granting Cloud Run Invoker to ${GEMINI_CALLER_SA}"
gcloud run services add-iam-policy-binding "${SERVICE_NAME}" \
  --member="serviceAccount:${GEMINI_CALLER_SA}" \
  --role="roles/run.invoker" \
  --region="${REGION}"

echo "[7/8] Running initial Cloud Build + deploy"
gcloud builds submit --config a2a/cloud_run/cloudbuild.yaml .

SERVICE_URL="$(gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" --format='value(status.url)')"

echo "[7b/8] Updating security environment variables on deployed service"
gcloud run services update "${SERVICE_NAME}" \
  --region "${REGION}" \
  --update-env-vars "EXPECTED_CALLER_SA=${GEMINI_CALLER_SA},EXPECTED_AUDIENCE=${SERVICE_URL}"

echo "[8/8] Gemini Enterprise registration example (Admin API)"
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

echo ""
echo "[Optional] Set up off-hours scaling to save costs:"
echo "  ./a2a/cloud_run/schedule.sh"
echo "  (Scales to 0 instances weeknights 9pm-5am ET and all weekend)"
