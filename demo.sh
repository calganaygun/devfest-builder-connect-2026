#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:---dry-run}"
[[ "$MODE" == --dry-run || "$MODE" == --apply ]] || { echo "Usage: $0 [--dry-run|--apply]" >&2; exit 2; }
: "${PROJECT_ID:?Set PROJECT_ID}"
SUFFIX="${SUFFIX:-$(printf %s "$PROJECT_ID" | tr -cd 'a-z0-9' | tail -c 12)}"
INPUT_BUCKET="${INPUT_BUCKET:-${PROJECT_ID}-signal-in-${SUFFIX}}"
OUTPUT_BUCKET="${OUTPUT_BUCKET:-${PROJECT_ID}-signal-out-${SUFFIX}}"
REPORT="${REPORT:-samples/01-heat.json}"
NAME="reports/$(basename "$REPORT")"
if [[ "$MODE" == --dry-run ]]; then
  printf 'DRY RUN: gcloud storage cp %q %q\n' "$REPORT" "gs://${INPUT_BUCKET}/${NAME}"
  printf 'DRY RUN: gcloud storage ls %q\n' "gs://${OUTPUT_BUCKET}/briefs/"
  printf 'DRY RUN: gcloud storage cat gs://%s/briefs/<computed-object-name>.json\n' "$OUTPUT_BUCKET"
  exit 0
fi
gcloud storage cp "$REPORT" "gs://${INPUT_BUCKET}/${NAME}"
GENERATION="$(gcloud storage ls -L "gs://${INPUT_BUCKET}/${NAME}" | awk '/Generation:/ {print $2; exit}')"
[[ -n "$GENERATION" ]] || { echo 'Could not resolve uploaded object generation' >&2; exit 1; }
RESULT="$(python - "$NAME" "$GENERATION" <<'PY'
import hashlib, sys
print('briefs/' + hashlib.sha256(f'{sys.argv[1]}\0{sys.argv[2]}'.encode()).hexdigest()[:24] + '.json')
PY
)"
for attempt in {1..24}; do
  if gcloud storage ls "gs://${OUTPUT_BUCKET}/${RESULT}" >/dev/null 2>&1; then
    gcloud storage cat "gs://${OUTPUT_BUCKET}/${RESULT}"
    exit 0
  fi
  sleep 5
done
echo 'Timed out waiting for brief. Check Eventarc trigger and Cloud Run logs.' >&2
exit 1
