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
run_with_retry() {
  local max_attempts="${MAX_ATTEMPTS:-12}"
  local delay="${RETRY_DELAY:-10}"
  local attempt=1
  if [[ "$MODE" == --dry-run ]]; then
    printf 'DRY RUN: '; printf '%q ' "$@"; printf '\n'
    return 0
  fi
  while true; do
    if "$@"; then
      break
    fi
    if [[ $attempt -ge $max_attempts ]]; then
      echo "Command failed after $max_attempts attempts: $*" >&2
      return 1
    fi
    echo "Principal or resource may not have propagated yet. Retrying in ${delay}s (attempt $attempt/$max_attempts)..." >&2
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}
ensure_service_account() {
  local name="$1"
  local display="$2"
  local email="${name}@${PROJECT_ID}.iam.gserviceaccount.com"
  if [[ "$MODE" == --dry-run ]]; then
    printf 'DRY RUN: gcloud iam service-accounts describe %q --project=%q >/dev/null 2>&1 || gcloud iam service-accounts create %q --display-name=%q --project=%q\n' \
      "$email" "$PROJECT_ID" "$name" "$display" "$PROJECT_ID"
  elif ! gcloud iam service-accounts describe "$email" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud iam service-accounts create "$name" --display-name="$display" --project="$PROJECT_ID"
  fi
}
ensure_bucket() {
  local bucket="$1"
  if [[ "$MODE" == --dry-run ]]; then
    printf 'DRY RUN: gcloud storage buckets describe %q >/dev/null 2>&1 || gcloud storage buckets create %q --project=%q --location=%q --uniform-bucket-level-access\n' \
      "gs://${bucket}" "gs://${bucket}" "$PROJECT_ID" "$REGION"
  elif ! gcloud storage buckets describe "gs://${bucket}" >/dev/null 2>&1; then
    gcloud storage buckets create "gs://${bucket}" --project="$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access
  fi
}
ensure_trigger() {
  if [[ "$MODE" == --dry-run ]]; then
    printf 'DRY RUN: gcloud eventarc triggers describe %q --location=%q --project=%q >/dev/null 2>&1 || gcloud eventarc triggers create %q ...\n' \
      "$TRIGGER" "$REGION" "$PROJECT_ID" "$TRIGGER"
  elif ! gcloud eventarc triggers describe "$TRIGGER" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud eventarc triggers create "$TRIGGER" --location="$REGION" --project="$PROJECT_ID" \
      --destination-run-service="$SERVICE" --destination-run-region="$REGION" \
      --event-filters="type=google.cloud.storage.object.v1.finalized" --event-filters="bucket=${INPUT_BUCKET}" \
      --service-account="$TRIGGER_SA"
  fi
}
if [[ "$MODE" == --apply ]]; then
  for binary in gcloud; do command -v "$binary" >/dev/null || { echo "$binary is required" >&2; exit 1; }; done
fi
run gcloud config set project "$PROJECT_ID"
run gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  eventarc.googleapis.com pubsub.googleapis.com storage.googleapis.com aiplatform.googleapis.com iam.googleapis.com
ensure_bucket "$INPUT_BUCKET"
ensure_bucket "$OUTPUT_BUCKET"
run gcloud storage buckets update "gs://${INPUT_BUCKET}" --versioning
ensure_service_account signal-runtime "Signal Room runtime"
ensure_service_account signal-trigger "Signal Room Eventarc"
run gcloud storage buckets add-iam-policy-binding "gs://${INPUT_BUCKET}" --member="serviceAccount:${RUNTIME_SA}" --role=roles/storage.objectViewer
run gcloud storage buckets add-iam-policy-binding "gs://${OUTPUT_BUCKET}" --member="serviceAccount:${RUNTIME_SA}" --role=roles/storage.objectUser
run gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${RUNTIME_SA}" --role=roles/aiplatform.user
run gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${TRIGGER_SA}" --role=roles/eventarc.eventReceiver
if [[ "$MODE" == --apply ]]; then
  if command -v gsutil >/dev/null 2>&1; then
    STORAGE_AGENT="$(gsutil kms serviceaccount -p "$PROJECT_ID" | tr -d '[:space:]')"
  else
    curl -s -f -X GET -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      "https://storage.googleapis.com/storage/v1/projects/${PROJECT_ID}/serviceAccount" >/dev/null 2>&1 || true
    STORAGE_AGENT="$(gcloud storage service-agent --project="$PROJECT_ID" | tr -d '[:space:]')"
  fi
else
  STORAGE_AGENT="<storage-service-agent-resolved-on-apply>"
fi
run_with_retry gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${STORAGE_AGENT}" --role=roles/pubsub.publisher
run gcloud run deploy "$SERVICE" --source=app --region="$REGION" --project="$PROJECT_ID" \
  --service-account="$RUNTIME_SA" --no-allow-unauthenticated --memory=1Gi --timeout=180 \
  --max-instances=3 --set-env-vars="INPUT_BUCKET=${INPUT_BUCKET},OUTPUT_BUCKET=${OUTPUT_BUCKET},GOOGLE_CLOUD_PROJECT=${PROJECT_ID},MODEL=gemini-2.5-flash"
run gcloud run services add-iam-policy-binding "$SERVICE" --region="$REGION" --project="$PROJECT_ID" \
  --member="serviceAccount:${TRIGGER_SA}" --role=roles/run.invoker
ensure_trigger
if [[ "$MODE" == --apply ]]; then
  printf '\nReady: INPUT_BUCKET=%s OUTPUT_BUCKET=%s REGION=%s\n' "$INPUT_BUCKET" "$OUTPUT_BUCKET" "$REGION"
  echo 'Allow up to two minutes for trigger propagation before first upload.'
fi
