#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == --apply ]] || { echo 'Usage: cleanup-gcloud.sh --apply' >&2; exit 2; }
: "${PROJECT_ID:?Set PROJECT_ID}"
REGION="${REGION:-europe-west3}"
SUFFIX="${SUFFIX:-$(printf %s "$PROJECT_ID" | tr -cd 'a-z0-9' | tail -c 12)}"
gcloud eventarc triggers delete "${TRIGGER:-signal-room-finalized}" --location="$REGION" --project="$PROJECT_ID" --quiet
gcloud run services delete "${SERVICE:-signal-room}" --region="$REGION" --project="$PROJECT_ID" --quiet
gcloud storage rm -r "gs://${INPUT_BUCKET:-${PROJECT_ID}-signal-in-${SUFFIX}}" "gs://${OUTPUT_BUCKET:-${PROJECT_ID}-signal-out-${SUFFIX}}"
echo 'Service and buckets removed. Review project IAM grants and build artifacts if needed.'
