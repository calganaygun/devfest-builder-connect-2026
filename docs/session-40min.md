# Speaker run of show: 40 minutes

**Title:** Event-Driven AI Pipelines on GCP: From Eventarc to LLMs  
**Project:** Signal Room  
**Audience:** Cloud developers with basic CLI experience  
**Promise:** Build a working event-to-AI pipeline and show what happens when delivery repeats or processing fails.

| Clock | Slide / action | Time |
|---|---|---:|
| 00:00–03:00 | 1. Cold open and incident | 3 min |
| 03:00–06:00 | 2. The contract and architecture | 3 min |
| 06:00–09:00 | 3. What success looks like | 3 min |
| 09:00–13:00 | 4. Buckets, identities, APIs | 4 min |
| 13:00–18:00 | 5. The Cloud Run worker | 5 min |
| 18:00–22:00 | 6. Eventarc trigger | 4 min |
| 22:00–29:00 | 7. First event, result and follow-up | 7 min |
| 29:00–34:00 | 8. Duplicate and failure drill | 5 min |
| 34:00–37:00 | 9. Operational decisions | 3 min |
| 37:00–40:00 | 10. Recap and Q&A | 3 min |

## 1. Cold open (00:00–03:00)

“At 2:20 p.m., a tram stops on Grunwaldzki Bridge. The air conditioning is off. There are 45 passengers and one may be faint. Someone sends a field report. A human dispatcher needs a concise, trustworthy brief, and the system needs to handle the next report too.”

Pause. “Today we will build that pipeline from a terminal. One object upload becomes a structured brief. Then we will deliberately ask what happens when the same event arrives twice and when the model is unavailable.” Introduce yourself in one sentence. State that the scenario and reports are fictional, and that an operator reviews all suggestions.

## 2. Architecture (03:00–06:00)

Walk left to right: a JSON report under `reports/` in the input bucket; a finalized event; Eventarc; authenticated Cloud Run; Gemini through Vertex AI; a JSON brief in a separate output bucket. Explain why two buckets: direct Storage event filters match the bucket, not a wildcard object prefix, so writing into the source bucket would cause another event. Show the identity boundary between Eventarc and Cloud Run.

## 3. Contract (06:00–09:00)

Open `samples/01-heat.json`. Say: “This report contains observations, not instructions to the model. The prompt explicitly treats it as untrusted evidence.” Open `app/main.py` and point to the response schema: category, severity, summary, entities, suggested action, uncertainty. The final brief includes source bucket/name/generation and `review_required=true`. Do not claim a model's assessment is operational truth.

## 4. Foundation (09:00–13:00)

Run `bash deploy-gcloud.sh --dry-run` with exported project, region and suffix. On screen, highlight the API list, two buckets, input versioning, two service accounts and four role boundaries. Then run `bash deploy-gcloud.sh --apply`. **For a 40-minute stage demo, provision APIs and build cache before doors open**; if this creation runs long, use a preprovisioned disposable project and skip directly to the trigger and upload. Explain the source build can take several minutes.

## 5. Worker (13:00–18:00)

Show `app/main.py` in three short stops. First, the CloudEvent `ce-type` and JSON body. Second, download the exact input generation and reject oversized or malformed input. Third, ask Gemini for JSON, then write with a create-only precondition. Describe the race: two deliveries may both call Gemini, but only one output write wins. Run `python -m pytest -q tests` to demonstrate the HTTP contract locally.

## 6. Eventarc (18:00–22:00)

Show the created trigger or run the trigger command visible in `deploy-gcloud.sh`. The event type is `google.cloud.storage.object.v1.finalized`, and the bucket filter exactly matches the input bucket. The trigger identity has `eventarc.eventReceiver` and `run.invoker`; the Storage service agent has `pubsub.publisher`. The service remains private. Trigger propagation can take roughly two minutes, so allow for it before uploading.

## 7. Live reports (22:00–29:00)

Run `bash demo.sh --apply`. It uploads the first report, resolves its object generation, computes the stable brief name, polls, and prints the JSON. Read the summary and the uncertainty aloud. Then run `REPORT=samples/02-followup.json bash demo.sh --apply`. Compare severity and facts. Ask: “What changed in the source report, and what did the model infer?” If the brief does not arrive, show `gcloud run services logs read signal-room --region="$REGION" --project="$PROJECT_ID" --limit=30` and `gcloud eventarc triggers describe signal-room-finalized --location="$REGION" --project="$PROJECT_ID"`; switch to the saved local HTTP test and sample contract while investigating. Do not invent a model output on stage.

## 8. Replays and failure (29:00–34:00)

Explain at-least-once delivery with a possible repeated event. In `test_app.py`, show one event accepted, a temporary error returning 503, and invalid input acknowledged with 200 to avoid a poison-message loop. Point at `result_name(name, generation)` and the `if_generation_match=0` write precondition. Uploading the same filename again creates a new generation, which correctly creates a new brief. Optional live drill: corrupt a `reports/invalid.json` file, upload it, and inspect logs. Note that this exercise does not establish exactly-once Gemini calls.

## 9. Operations (34:00–37:00)

Be precise about what remains before production: quarantine invalid objects, define retry lifetime/dead-letter handling, alert on stuck jobs, measure model quality and costs, redact sensitive reports, and require human review. IAM and a private endpoint protect the path, but the model still needs evaluation against prompt injection and unsupported claims.

## 10. Close (37:00–40:00)

Recap the progression: object generation, event delivery, private worker, structured AI output, create-only result. Invite questions. “If you only remember one design choice, key your result to the input generation. It gives an operator a traceable answer and gives retries a safe destination.” Mention the Terraform variant and cleanup. Keep Q&A within the last three minutes.

## Rehearsal gates

Before the event: confirm billing, quota and permissions; run actual `--apply` in a disposable project; upload both reports; inspect both JSON outputs and logs; record real durations; reset buckets if needed; leave a provisioned backup project ready. This repository has local dry runs and tests, but cloud behavior cannot be certified without access to your project.
