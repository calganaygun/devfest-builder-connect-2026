# Signal Room

**Event-Driven AI Pipelines on GCP: From Eventarc to LLMs**  
Google DevFest 2026 Wrocław demo kit

A tram incident report arrives in Cloud Storage. Eventarc delivers its finalized event to a private Cloud Run service. Gemini on Vertex AI returns a structured brief for a human operator. The brief lands in a *different* bucket, which prevents an output event from retriggering the pipeline.

## Run the 40-minute gcloud session

Prerequisites: a **billed** Google Cloud project, permission to enable APIs and administer IAM, Cloud Run, Cloud Build, Storage and Eventarc, and `gcloud` authenticated in Cloud Shell. Gemini model access and quota must be available. This creates billable resources. Use a disposable project. Bucket names must be globally unique; set `SUFFIX` if the defaults conflict.

```bash
export PROJECT_ID='your-billed-project-id'
export REGION='europe-west3'
export SUFFIX='devfest26'
bash deploy-gcloud.sh --dry-run
bash deploy-gcloud.sh --apply
# Wait about two minutes for Eventarc trigger propagation.
bash demo.sh --dry-run
bash demo.sh --apply
REPORT=samples/02-followup.json bash demo.sh --apply
gcloud run services logs read signal-room --region="$REGION" --project="$PROJECT_ID" --limit=30
```

The service requires authentication. Only the Eventarc trigger identity gets `run.invoker`. Its runtime identity can read the report bucket, read/write the brief bucket, and use Vertex AI. Cloud Storage's service agent publishes events. The input bucket has versioning enabled; each `{object name, generation}` produces a stable output name. The result upload uses `if_generation_match=0`, so a repeated delivery cannot overwrite a completed brief. Concurrent duplicates *can* invoke Gemini twice before one wins the write race, so this is output idempotency, not exactly-once model billing.

Inspect the briefs and compare the two incidents:

```bash
gcloud storage ls "gs://${PROJECT_ID}-signal-out-${SUFFIX}/briefs/"
gcloud storage cat "gs://${PROJECT_ID}-signal-out-${SUFFIX}/briefs/<name>.json"
gcloud eventarc triggers describe signal-room-finalized --location="$REGION" --project="$PROJECT_ID"
```

### Failure behavior

Malformed or oversized input gets HTTP 200 with `invalid` in the log and remains in the input bucket for manual review. A transient AI or Storage failure gets HTTP 503, asking Eventarc to redeliver. A replay of an already completed input returns `duplicate`. These are deliberate demo policies, not a complete operational incident queue. For production, send invalid objects to a quarantine workflow, configure retry age and a dead-letter strategy, add alerting and retention, evaluate prompt injection and model output quality, and define a human escalation process. Never dispatch emergency services from this model output.

### 20-minute Terraform variation

Prebuild the same app image before the talk in Artifact Registry (or provide an already built image) and place its URI in `infra/terraform/terraform.tfvars`. The Terraform stack creates **separate** `-tf` service accounts, Cloud Run service and trigger, plus buckets; it does not import or modify the gcloud demo. The 20-minute segment assumes the image and provider plugin are cached, API/IAM permissions are ready, and the project is billed.

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars  # edit project_id, suffix, image
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
gcloud storage cp ../../samples/01-heat.json "gs://$(terraform output -raw input_bucket)/reports/01-heat.json"
gcloud storage ls "gs://$(terraform output -raw output_bucket)/briefs/"
# After the event, and only in the disposable demo project:
terraform destroy
```

If you need to build the image, create an Artifact Registry Docker repository and run `gcloud builds submit app --tag REGION-docker.pkg.dev/PROJECT/REPOSITORY/worker:demo`. Grant the Cloud Build identity appropriate repository write permission if your project does not do so by default. Build before the 20-minute variant.

## Local verification

```bash
python -m pip install -r app/requirements.txt pytest
python -m pytest -q tests
PROJECT_ID=example-project SUFFIX=demo26 bash deploy-gcloud.sh --dry-run
PROJECT_ID=example-project SUFFIX=demo26 bash demo.sh --dry-run
bash -n deploy-gcloud.sh demo.sh cleanup-gcloud.sh
```

`--dry-run` prints the commands without accessing the project. It cannot validate IAM, quota, regional model availability, build permissions, billing, or actual Eventarc delivery. For a cloud rehearsal, run `--apply` in a disposable billed project and inspect the output object before the event.

## Clean up

```bash
PROJECT_ID=your-billed-project-id SUFFIX=devfest26 REGION=europe-west3 bash cleanup-gcloud.sh --apply
```

Cleanup removes the trigger, service and buckets, including stored data. Project IAM grants, service accounts and source-build artifacts remain: inspect and remove them in the disposable project or delete the project. Terraform's `destroy` removes its managed resources and objects, since `force_destroy=true` is set for the demo.

## Current references

- [Route Cloud Storage events to Cloud Run](https://docs.cloud.google.com/eventarc/standard/docs/run/route-trigger-cloud-storage)
- [Authenticate Cloud Run services](https://docs.cloud.google.com/run/docs/authenticating/overview)
- [Gemini API on Vertex AI quickstart](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/start/quickstart)
- [Terraform Eventarc trigger resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/eventarc_trigger)
