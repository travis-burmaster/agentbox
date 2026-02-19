# AgentBox A2A Wrapper for Gemini Enterprise

This directory provides an A2A (Agent-to-Agent protocol) HTTP layer so Gemini Enterprise can call AgentBox as a sub-agent on Cloud Run.

## Architecture

```text
+-------------------------------+
| Gemini Enterprise             |
| (Agent Gallery + Orchestrator)|
+---------------+---------------+
                |
                | A2A JSON-RPC over HTTPS + IAM identity token
                v
+---------------+---------------+
| Cloud Run: agentbox-a2a       |
| FastAPI A2A wrapper           |
| - /.well-known/agent.json     |
| - POST /  (tasks/send,get)    |
| - IAM token validation         |
+---------------+---------------+
                |
                | Local bridge (CLI or gateway)
                v
+---------------+---------------+
| AgentBox / OpenClaw runtime   |
| - openclaw system event       |
| - optional gateway on :3000   |
+-------------------------------+
```

## How A2A works here

1. Gemini Enterprise discovers the agent card at `/.well-known/agent.json`.
2. Gemini sends A2A JSON-RPC requests to `POST /`.
3. Wrapper validates IAM Bearer token (Google-signed identity token).
4. Wrapper translates task text to OpenClaw invocation.
5. Wrapper returns A2A artifact response (`tasks/send`) or status lookup behavior (`tasks/get`).

Supported methods:
- `tasks/send`
- `tasks/get` (stateless wrapper; returns not-found for prior tasks)

## Files

- `server.py`: FastAPI A2A server.
- `agent_card.json`: Agent descriptor consumed by Gemini.
- `requirements.txt`: Python deps.
- `Dockerfile.a2a`: standalone container image.
- `cloud_run/service.yaml`: service manifest template.
- `cloud_run/cloudbuild.yaml`: build + deploy pipeline.
- `cloud_run/setup.sh`: one-shot bootstrap script.

## Prerequisites

- Google Cloud project with billing enabled.
- Gemini Enterprise entitlement/license.
- `gcloud` CLI authenticated and configured.
- Cloud Run, Cloud Build, Secret Manager APIs enabled.
- Existing AgentBox/OpenClaw runtime design for request execution.

## Deploy step-by-step

1. Set project and region:

```bash
gcloud config set project YOUR_PROJECT_ID
export PROJECT_ID="YOUR_PROJECT_ID"
export REGION="us-central1"
```

2. Build and deploy with Cloud Build:

```bash
gcloud builds submit --config a2a/cloud_run/cloudbuild.yaml .
```

3. Capture Cloud Run URL:

```bash
SERVICE_URL="$(gcloud run services describe agentbox-a2a --region ${REGION} --format='value(status.url)')"
echo "$SERVICE_URL"
```

4. Configure strict caller + audience validation:

```bash
export GEMINI_CALLER_SA="gemini-enterprise-caller@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud run services update agentbox-a2a \
  --region ${REGION} \
  --update-env-vars EXPECTED_CALLER_SA=${GEMINI_CALLER_SA},EXPECTED_AUDIENCE=${SERVICE_URL}
```

5. Grant invoker role to Gemini caller service account:

```bash
gcloud run services add-iam-policy-binding agentbox-a2a \
  --region ${REGION} \
  --member="serviceAccount:${GEMINI_CALLER_SA}" \
  --role="roles/run.invoker"
```

6. Confirm unauthenticated access is disabled:

```bash
gcloud run services get-iam-policy agentbox-a2a --region ${REGION}
```

## One-shot setup

Use:

```bash
PROJECT_ID=YOUR_PROJECT_ID GEMINI_CALLER_SA=caller@YOUR_PROJECT_ID.iam.gserviceaccount.com \
  a2a/cloud_run/setup.sh
```

`setup.sh` enables APIs, creates service account, grants invoker, deploys, and prints Gemini registration API example.

## Register in Gemini Enterprise Agent Gallery

### UI path

1. Open Gemini Enterprise Admin.
2. Go to Agent Gallery / Agent management.
3. Add external/sub-agent using A2A endpoint.
4. Provide:
   - Endpoint URL: `${SERVICE_URL}`
   - Agent card URL: `${SERVICE_URL}/.well-known/agent.json`
5. Save and run a test task.

### API path (example)

```bash
curl -X POST "https://geminienterprise.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/agents" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "AgentBox",
    "description": "AgentBox A2A sub-agent",
    "a2aConfig": {
      "endpoint": "'"${SERVICE_URL}"'",
      "agentCardUrl": "'"${SERVICE_URL}"'/.well-known/agent.json"
    }
  }'
```

## Testing before Gemini registration

Obtain identity token for an allowed caller service account:

```bash
TOKEN="$(gcloud auth print-identity-token)"
```

Call agent card:

```bash
curl -sS "${SERVICE_URL}/.well-known/agent.json" | jq .
```

Call A2A `tasks/send`:

```bash
curl -sS -X POST "${SERVICE_URL}/" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "task-123",
    "method": "tasks/send",
    "params": {
      "id": "task-123",
      "message": {
        "role": "user",
        "parts": [{"type": "text", "text": "What files are in the workspace?"}]
      }
    }
  }' | jq .
```

Call A2A `tasks/get`:

```bash
curl -sS -X POST "${SERVICE_URL}/" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "get-123",
    "method": "tasks/get",
    "params": {"id": "task-123"}
  }' | jq .
```

## Security model

- IAM-only invocation (`--no-allow-unauthenticated`).
- Cloud Run ingress restricted to `internal-and-cloud-load-balancing`.
- A2A server validates Google-signed identity token and verifies caller service account allowlist.
- No user-facing OpenClaw endpoint exposure.
- Wrapper timeout is capped at 55 minutes to stay under Cloud Run 60-minute max.

## Important gotcha

Gemini sends one inbound Bearer token for the A2A call. Do not forward/chaining this token to downstream services. Use Workload Identity and/or Secret Manager for downstream auth from Cloud Run.

## Runtime behavior notes

- Stateless by design: no in-memory task persistence across requests.
- `tasks/get` returns task-not-found for historical tasks unless you add external persistence.
- Backend execution mode:
  - `AGENTBOX_BACKEND=cli` (default): runs `openclaw system event --text ... --mode now`
  - `AGENTBOX_BACKEND=gateway`: posts to `${AGENTBOX_GATEWAY_URL}/system/event`
