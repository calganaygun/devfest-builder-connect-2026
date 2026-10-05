#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:---dry-run}"
[[ "$MODE" == --dry-run || "$MODE" == --apply ]] || { echo "Usage: $0 [--dry-run|--apply]" >&2; exit 2; }
: "${PROJECT_ID:?Set PROJECT_ID to a billed Google Cloud project}"
REGION="${REGION:-europe-west3}"
SUFFIX="${SUFFIX:-$(printf %s "$PROJECT_ID" | tr -cd 'a-z0-9' | tail -c 12)}"
INPUT_BUCKET="${INPUT_BUCKET:-${PROJECT_ID}-signal-in-${SUFFIX}}"
OUTPUT_BUCKET="${OUTPUT_BUCKET:-${PROJECT_ID}-signal-out-${SUFFIX}}"
SERVICE="${SERVICE:-signal-room}"
TRIGGER="${TRIGGER:-signal-room-finalized}"
RUNTIME_SA="signal-runtime@${PROJECT_ID}.iam.gserviceaccount.com"
TRIGGER_SA="signal-trigger@${PROJECT_ID}.iam.gserviceaccount.com"

run() { if [[ "$MODE" == --dry-run ]]; then printf 'DRY RUN: '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }
if [[ "$MODE" == --apply ]]; then
  for binary in gcloud; do command -v "$binary" >/dev/null || { echo "$binary is required" >&2; exit 1; }; done
fi
run gcloud config set project "$PROJECT_ID"
run gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  eventarc.googleapis.com pubsub.googleapis.com storage.googleapis.com aiplatform.googleapis.com iam.googleapis.com
run gcloud storage buckets create "gs://${INPUT_BUCKET}" --project="$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access
run gcloud storage buckets create "gs://${OUTPUT_BUCKET}" --project="$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access
run gcloud storage buckets update "gs://${INPUT_BUCKET}" --versioning
run gcloud iam service-accounts create signal-runtime --display-name="Signal Room runtime"
run gcloud iam service-accounts create signal-trigger --display-name="Signal Room Eventarc"
run gcloud storage buckets add-iam-policy-binding "gs://${INPUT_BUCKET}" --member="serviceAccount:${RUNTIME_SA}" --role=roles/storage.objectViewer
run gcloud storage buckets add-iam-policy-binding "gs://${OUTPUT_BUCKET}" --member="serviceAccount:${RUNTIME_SA}" --role=roles/storage.objectUser
run gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${RUNTIME_SA}" --role=roles/aiplatform.user
run gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${TRIGGER_SA}" --role=roles/eventarc.eventReceiver
if [[ "$MODE" == --apply ]]; then
  STORAGE_AGENT="$(gcloud storage service-agent --project="$PROJECT_ID")"
else
  STORAGE_AGENT="<storage-service-agent-resolved-on-apply>"
fi
run gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${STORAGE_AGENT}" --role=roles/pubsub.publisher
run gcloud run deploy "$SERVICE" --source=app --region="$REGION" --project="$PROJECT_ID" \
  --service-account="$RUNTIME_SA" --no-allow-unauthenticated --memory=1Gi --timeout=180 \
  --max-instances=3 --set-env-vars="INPUT_BUCKET=${INPUT_BUCKET},OUTPUT_BUCKET=${OUTPUT_BUCKET},GOOGLE_CLOUD_PROJECT=${PROJECT_ID},MODEL=gemini-2.5-flash"
run gcloud run services add-iam-policy-binding "$SERVICE" --region="$REGION" --project="$PROJECT_ID" \
  --member="serviceAccount:${TRIGGER_SA}" --role=roles/run.invoker
run gcloud eventarc triggers create "$TRIGGER" --location="$REGION" --project="$PROJECT_ID" \
  --destination-run-service="$SERVICE" --destination-run-region="$REGION" \
  --event-filters="type=google.cloud.storage.object.v1.finalized" --event-filters="bucket=${INPUT_BUCKET}" \
  --service-account="$TRIGGER_SA"
if [[ "$MODE" == --apply ]]; then
  printf '\nReady: INPUT_BUCKET=%s OUTPUT_BUCKET=%s REGION=%s\n' "$INPUT_BUCKET" "$OUTPUT_BUCKET" "$REGION"
  echo 'Allow up to two minutes for trigger propagation before first upload.'
fi
