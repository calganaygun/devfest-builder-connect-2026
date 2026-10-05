# Twenty-minute Terraform variant

This is a separate, compressed infrastructure segment. Prebuild and test the image before entering the room. Precache the Google provider and authenticate Terraform. Use a fresh suffix so this stack does not collide with the gcloud exercise.

| Clock | Stage action | English talking point |
|---|---|---|
| 00:00–02:00 | Show the incident input and output brief | “The application contract is the same. Today Terraform owns the cloud resources.” |
| 02:00–05:00 | Open `main.tf` | “Two buckets break an event loop. Two identities separate delivery from model and storage access.” |
| 05:00–09:00 | `terraform init`, `fmt -check`, `validate`, `plan -out=tfplan` | “The plan is the reviewable change. Check the Cloud Run image, region and IAM members.” |
| 09:00–14:00 | `terraform apply tfplan` | “The trigger listens for a finalized object in exactly this bucket and invokes a private service.” |
| 14:00–17:00 | Upload sample and read brief | “The generated brief records the object generation and requests human review.” |
| 17:00–20:00 | Discuss retries, limitations and Q&A | “The create-only write controls duplicate outputs; it cannot prevent duplicate AI calls.” |

Keep a completed `plan` and a preprovisioned backup stack ready. If provider download or permissions delay the apply, use the backup stack for the upload demo and show the plan as the configuration artifact. Destroy the disposable stack after the session. Never `terraform destroy` a shared project without reviewing its plan.
