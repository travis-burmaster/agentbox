# AgentBox A2A — Cloud Run + Gemini Enterprise

Deploy AgentBox as a Gemini Enterprise sub-agent on Google Cloud Run using the
[Agent-to-Agent (A2A) protocol](https://a2a-protocol.org/latest/).  
**Humans never reach OpenClaw directly — all access flows through Gemini Enterprise over A2A.**

---

## Architecture


The A2A container is **self-contained** — it bundles both the OpenClaw gateway
and the FastAPI A2A wrapper in a single image, managed by supervisord.
Only port 8080 (FastAPI) is exposed; the OpenClaw gateway on port 3000 stays
internal to the container.

```
┌──────────────────────────────────┐
│  Gemini Enterprise               │
│  (Agent Gallery + Orchestrator)  │
└────────────────┬─────────────────┘
                 │  HTTPS  A2A JSON-RPC
                 │  IAM identity token (Bearer)
                 ▼
┌──────────────────────────────────────────────┐
│  Cloud Run: agentbox-a2a (single container)  │
│                                              │
│  ┌─ supervisord ───────────────────────────┐ │
│  │                                         │ │
│  │  [uvicorn-a2a]        :8080 (external)  │ │
│  │   FastAPI A2A wrapper                   │ │
│  │   ● GET  /.well-known/agent.json        │ │
│  │   ● POST /  (tasks/send, get)           │ │
│  │   ● IAM token validation (2-layer)      │ │
│  │        │                                │ │
│  │        │ localhost:3000                  │ │
│  │        ▼                                │ │
│  │  [openclaw-gateway]   :3000 (internal)  │ │
│  │   OpenClaw runtime                      │ │
│  │                                         │ │
│  └─────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

**Security: two-layer lock**
1. **Cloud Run IAM** — `--no-allow-unauthenticated`; only Gemini Enterprise SA has `roles/run.invoker`
2. **App-level** — server checks Bearer token is Google-signed AND `token.email == EXPECTED_CALLER_SA`
3. **Internal gateway** — OpenClaw gateway on port 3000 is never exposed externally

---

## Prerequisites

| Tool | Install |
|------|---------|
| `gcloud` CLI | https://cloud.google.com/sdk/docs/install |
| `docker` | https://docs.docker.com/get-docker/ |
| `jq` | `sudo apt-get install jq` / `brew install jq` |
| GCP project with billing | console.cloud.google.com |
| Gemini Enterprise license | Required to register the agent in Agent Gallery |

```bash
# Verify tools
gcloud version
docker version
jq --version
```

---

## Step 0 — Clone and set variables

Open a VS Code terminal (`Ctrl+`` ` on Windows/Linux, `Cmd+`` ` on Mac) and run:

```bash
# Clone (if you haven't already)
git clone https://github.com/travis-burmaster/agentbox.git
cd agentbox
git checkout feat/a2a-cloud-run

# ── Set these once; all commands below use them ───────────────────────────────
export PROJECT_ID="YOUR_PROJECT_ID"           # e.g. my-gcp-project-123
export REGION="us-central1"                   # Cloud Run region
export SERVICE_NAME="agentbox-a2a"
export A2A_SA="${SERVICE_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Authenticate
gcloud auth login
gcloud config set project "${PROJECT_ID}"
gcloud auth application-default login
```

---

## Step 1 — Enable GCP APIs

```bash
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  artifactregistry.googleapis.com
```

---

## Step 2 — Create the Cloud Run service account

```bash
# Create SA (skip if it already exists)
gcloud iam service-accounts create "${SERVICE_NAME}" \
  --display-name="AgentBox A2A Cloud Run SA" \
  --project="${PROJECT_ID}"

# Confirm
gcloud iam service-accounts describe "${A2A_SA}"
```

---

## Step 3 — Find the Gemini Enterprise caller service account

Gemini Enterprise uses a managed service account to call your A2A endpoint.
Find it one of these ways:

**Option A — From GCP Console**
```
IAM & Admin → IAM → filter "discoveryengine" or "gemini"
Look for: service-{PROJECT_NUMBER}@gcp-sa-discoveryengine.iam.gserviceaccount.com
```

**Option B — From gcloud**
```bash
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')
echo "service-${PROJECT_NUMBER}@gcp-sa-discoveryengine.iam.gserviceaccount.com"
```

**Option C — From Gemini Enterprise Admin UI**
```
Gemini Enterprise Admin → Agent Gallery → Add agent → A2A
The caller SA is shown during the configuration flow.
```

Once you have it:
```bash
# Set it — replace with the actual SA from above
export GEMINI_CALLER_SA="service-XXXX@gcp-sa-discoveryengine.iam.gserviceaccount.com"
```

---

## Step 4 — Test locally with Docker (optional but recommended)

The image is self-contained: supervisord starts both the OpenClaw gateway
(port 3000, internal) and the FastAPI A2A wrapper (port 8080, exposed).

```bash
# Build the A2A image locally (includes Node.js + OpenClaw + Python + supervisord)
docker build -f a2a/Dockerfile.a2a -t agentbox-a2a:local .

# Run locally — skip real token validation by setting a dummy audience
docker run --rm -p 8080:8080 \
  -e EXPECTED_AUDIENCE="http://localhost:8080" \
  -e EXPECTED_CALLER_SA="test@test.com" \
  agentbox-a2a:local

# In a second terminal — test the health endpoint
curl -s http://localhost:8080/health | jq .

# Test the agent card (no auth required — A2A discovery standard)
curl -s http://localhost:8080/.well-known/agent.json | jq .

# Test a task (no real token in local mode — server will reject but shows routing works)
curl -s -X POST http://localhost:8080/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"t1","method":"tasks/send","params":{"id":"t1","message":{"role":"user","parts":[{"type":"text","text":"hello"}]}}}' \
  | jq .
```

Stop the local container when done: `Ctrl+C`

---

## Step 5 — Build and deploy to Cloud Run

```bash
# Submit to Cloud Build (builds Docker image + deploys via service.yaml)
gcloud builds submit \
  --config a2a/cloud_run/cloudbuild.yaml \
  --substitutions "_REGION=${REGION},_GEMINI_CALLER_SA=${GEMINI_CALLER_SA},_SERVICE_URL=" \
  --project "${PROJECT_ID}" \
  .

# Get the deployed URL
export SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
  --region "${REGION}" \
  --format='value(status.url)')
echo "Service URL: ${SERVICE_URL}"
```

---

## Step 6 — Set security environment variables

```bash
gcloud run services update "${SERVICE_NAME}" \
  --region "${REGION}" \
  --update-env-vars \
    "EXPECTED_CALLER_SA=${GEMINI_CALLER_SA},EXPECTED_AUDIENCE=${SERVICE_URL},SERVICE_URL=${SERVICE_URL}"
```

---

## Step 7 — Grant Gemini Enterprise SA invoker access

```bash
# Grant ONLY Gemini Enterprise SA — no other principals
gcloud run services add-iam-policy-binding "${SERVICE_NAME}" \
  --region "${REGION}" \
  --member="serviceAccount:${GEMINI_CALLER_SA}" \
  --role="roles/run.invoker"

# Verify — ONLY Gemini SA should appear under roles/run.invoker
gcloud run services get-iam-policy "${SERVICE_NAME}" \
  --region "${REGION}"
```

---

## Step 8 — Test the deployed endpoint

Before registering in Gemini, verify the endpoint works using impersonation of the Gemini SA:

```bash
# Get an identity token impersonating the Gemini SA
# (requires your account to have roles/iam.serviceAccountTokenCreator on GEMINI_CALLER_SA)
TOKEN=$(gcloud auth print-identity-token \
  --impersonate-service-account="${GEMINI_CALLER_SA}" \
  --audiences="${SERVICE_URL}")

# 1. Health check (no auth needed)
curl -s "${SERVICE_URL}/health" | jq .
# Expected: {"status": "ok", "issues": []}

# 2. Agent card (no auth needed — A2A discovery)
curl -s "${SERVICE_URL}/.well-known/agent.json" | jq .
# Expected: agent card JSON with correct "url" field = SERVICE_URL

# 3. A2A task — tasks/send
curl -s -X POST "${SERVICE_URL}/" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "test-001",
    "method": "tasks/send",
    "params": {
      "id": "test-001",
      "message": {
        "role": "user",
        "parts": [{"type": "text", "text": "What is 2 + 2?"}]
      }
    }
  }' | jq .
# Expected: result with status.state="working" or "completed" + artifacts

# 4. Poll for result — tasks/get
curl -s -X POST "${SERVICE_URL}/" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": \"get-001\",
    \"method\": \"tasks/get\",
    \"params\": {\"id\": \"test-001\"}
  }" | jq .

# 5. Confirm unauthorized access is rejected (no token)
curl -s -X POST "${SERVICE_URL}/" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"x","method":"tasks/send","params":{}}' | jq .
# Expected: HTTP 401 + A2A error response
```

---

## Step 9 — Register in Gemini Enterprise Agent Gallery

### Option A — Admin UI (recommended for first time)

```
1. Go to: console.cloud.google.com → Gemini Enterprise → Agent Gallery
2. Click "Add agent" → "Custom agent via A2A"
3. Fill in:
     Display name:   AgentBox
     Endpoint URL:   <paste SERVICE_URL>
     Agent card URL: <paste SERVICE_URL>/.well-known/agent.json
4. Click "Test connection" — should show green
5. Save and enable for your org
```

### Option B — Admin API

```bash
curl -s -X POST \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines/gemini-enterprise/assistants/default_assistant/agents" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d "{
    \"displayName\": \"AgentBox\",
    \"description\": \"AgentBox AI engineering sub-agent powered by OpenClaw\",
    \"a2aAgentDefinition\": {
      \"jsonAgentCard\": $(curl -s ${SERVICE_URL}/.well-known/agent.json | jq -c . | jq -Rs .)
    }
  }" | jq .
```

---

## Step 10 — Verify end-to-end from Gemini

```
1. Open Gemini Enterprise chat (gemini.google.com/enterprise or your org's URL)
2. Type: "@AgentBox what files are in your workspace?"
3. Gemini should route the request to AgentBox via A2A and return the response
```

---

## Redeployment (after code changes)

```bash
# Rebuild and redeploy with latest commit
gcloud builds submit \
  --config a2a/cloud_run/cloudbuild.yaml \
  --substitutions "_REGION=${REGION},_GEMINI_CALLER_SA=${GEMINI_CALLER_SA},_SERVICE_URL=${SERVICE_URL}" \
  --project "${PROJECT_ID}" \
  .


 gcloud run deploy agentbox-a2a --image "${REGION}-docker.pkg.dev/${PROJECT_ID}/agentbox/agentbox-a2a:latest" --region "${REGION}"  --platform managed --no-allow-unauthenticated --cpu 2  --memory 1Gi  --timeout 3300 --concurrency 10  --execution-environment gen2 --set-env-vars "AGENTBOX_BACKEND=gateway,GOOGLE_CLOUD_PROJECT=${PROJECT_ID},EXPECTED_CALLER_SA=${GEMINI_CALLER_SA}" --service-account "agentbox-a2a@${PROJECT_ID}.iam.gserviceaccount.com" 
```

---

## Environment variable reference

| Variable | Required | Description |
|----------|----------|-------------|
| `EXPECTED_AUDIENCE` | ✅ | Cloud Run service URL (e.g. `https://agentbox-a2a-xxxx.a.run.app`) |
| `EXPECTED_CALLER_SA` | ✅ | Gemini Enterprise service account email (comma-separated for multiple) |
| `AGENTBOX_BACKEND` | optional | `gateway` (default) or `cli` |
| `AGENTBOX_GATEWAY_URL` | optional | OpenClaw gateway URL (default: `http://localhost:3000`) |
| `GOOGLE_CLOUD_PROJECT` | optional | GCP project ID for logging |
| `SERVICE_URL` | optional | Alias for `EXPECTED_AUDIENCE` |

---

## Troubleshooting

**`403 Forbidden` from Cloud Run (before reaching app)**
```bash
# Check IAM — only GEMINI_CALLER_SA should have run.invoker
gcloud run services get-iam-policy "${SERVICE_NAME}" --region "${REGION}"
# If missing, re-run Step 7
```

**`401 Unauthorized: Caller X is not in EXPECTED_CALLER_SA allowlist` (from app)**
```bash
# The Gemini SA email doesn't match what's in EXPECTED_CALLER_SA
# Check what SA Gemini is actually using via Cloud Logging:
gcloud logging read \
  'resource.type="cloud_run_revision" AND textPayload=~"Auth rejected"' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="table(timestamp, textPayload)"
# Update EXPECTED_CALLER_SA with the correct email and re-run Step 6
```

**`Server is missing EXPECTED_AUDIENCE configuration` (health check fails)**
```bash
# Re-run Step 6 to set the env vars
gcloud run services update "${SERVICE_NAME}" \
  --region "${REGION}" \
  --update-env-vars "EXPECTED_CALLER_SA=${GEMINI_CALLER_SA},EXPECTED_AUDIENCE=${SERVICE_URL}"
```

**`impersonate-service-account` fails in Step 8**
```bash
# Grant yourself token creator on the Gemini SA
gcloud iam service-accounts add-iam-policy-binding "${GEMINI_CALLER_SA}" \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountTokenCreator"
```

**View live logs**
```bash
gcloud run services logs tail "${SERVICE_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}"
```

---

## Security notes

- **Ingress:** `internal-and-cloud-load-balancing` — not directly reachable from the public internet without going through Google's infrastructure
- **Auth:** `--no-allow-unauthenticated` + app-level email check — two independent rejection layers
- **Token chaining:** Gemini injects one Bearer token for the A2A call. **Do not forward it downstream.** For downstream service auth, use [Workload Identity](https://cloud.google.com/run/docs/securing/service-identity) and/or [Secret Manager](https://cloud.google.com/secret-manager)
- **Rotating Gemini SA:** If Gemini's SA email changes, update `EXPECTED_CALLER_SA` and re-run Step 6 + Step 7
