#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == --apply ]] || { echo 'Usage: cleanup-gcloud.sh --apply' >&2; exit 2; }
: "${PROJECT_ID:?Set PROJECT_ID}"
REGION="${REGION:-europe-west3}"
SUFFIX="${SUFFIX:-$(printf %s "$PROJECT_ID" | tr -cd 'a-z0-9' | tail -c 12)}"
TRIGGER_NAME="${TRIGGER:-signal-room-finalized}"
SERVICE_NAME="${SERVICE:-signal-room}"
IN_BUCKET="${INPUT_BUCKET:-${PROJECT_ID}-signal-in-${SUFFIX}}"
OUT_BUCKET="${OUTPUT_BUCKET:-${PROJECT_ID}-signal-out-${SUFFIX}}"

if gcloud eventarc triggers describe "$TRIGGER_NAME" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud eventarc triggers delete "$TRIGGER_NAME" --location="$REGION" --project="$PROJECT_ID" --quiet
else
  echo "Eventarc trigger ${TRIGGER_NAME} not found, skipping."
fi

if gcloud run services describe "$SERVICE_NAME" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud run services delete "$SERVICE_NAME" --region="$REGION" --project="$PROJECT_ID" --quiet
else
  echo "Cloud Run service ${SERVICE_NAME} not found, skipping."
fi

for bucket in "$IN_BUCKET" "$OUT_BUCKET"; do
  if gcloud storage buckets describe "gs://${bucket}" >/dev/null 2>&1; then
    gcloud storage rm -r "gs://${bucket}"
  else
    echo "Bucket gs://${bucket} not found, skipping."
  fi
done
echo 'Service and buckets removed. Review project IAM grants and build artifacts if needed.'
