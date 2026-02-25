#!/bin/bash
# Deploy AgentBox Marketing to GCP Cloud Run
set -euo pipefail

PROJECT=${GCP_PROJECT:?Set GCP_PROJECT}
REGION=${GCP_REGION:-us-central1}
REPO="${REGION}-docker.pkg.dev/${PROJECT}/agentbox/agentbox-marketing"
TAG=$(git rev-parse --short HEAD)

echo "🔨 Building container..."
docker build -t "${REPO}:${TAG}" -t "${REPO}:latest" .

echo "📦 Pushing to Artifact Registry..."
docker push "${REPO}:${TAG}"
docker push "${REPO}:latest"

echo "🚀 Deploying to Cloud Run..."
gcloud run deploy agentbox-marketing \
  --image "${REPO}:${TAG}" \
  --region "${REGION}" \
  --project "${PROJECT}" \
  --min-instances 0 \
  --max-instances 10 \
  --memory 2Gi \
  --cpu 2 \
  --concurrency 1 \
  --timeout 300 \
  --no-allow-unauthenticated \
  --update-env-vars "IMAGE_TAG=${TAG}"

echo "✅ Deployed: ${REPO}:${TAG}"
echo "   Cloud Run URL: $(gcloud run services describe agentbox-marketing \
  --region ${REGION} --project ${PROJECT} --format 'value(status.url)')"
