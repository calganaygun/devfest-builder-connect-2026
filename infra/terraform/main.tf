locals {
  input_bucket  = "${var.project_id}-signal-in-${var.suffix}"
  output_bucket = "${var.project_id}-signal-out-${var.suffix}"
}

resource "google_project_service" "api" {
  for_each = toset([
    "run.googleapis.com", "eventarc.googleapis.com", "pubsub.googleapis.com",
    "storage.googleapis.com", "aiplatform.googleapis.com", "iam.googleapis.com"
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_storage_bucket" "input" {
  name                        = local.input_bucket
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true # Demo only: destroys all uploaded reports.
  versioning { enabled = true }
  depends_on = [google_project_service.api]
}
resource "google_storage_bucket" "output" {
  name                        = local.output_bucket
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true # Demo only: destroys all generated briefs.
  depends_on = [google_project_service.api]
}
resource "google_service_account" "runtime" {
  account_id   = "signal-runtime-tf"
  display_name = "Signal Room Terraform runtime"
  project      = var.project_id
  depends_on   = [google_project_service.api]
}
resource "google_service_account" "trigger" {
  account_id   = "signal-trigger-tf"
  display_name = "Signal Room Terraform Eventarc"
  project      = var.project_id
  depends_on   = [google_project_service.api]
}
resource "google_storage_bucket_iam_member" "read_input" {
  bucket = google_storage_bucket.input.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.runtime.email}"
}
resource "google_storage_bucket_iam_member" "write_output" {
  bucket = google_storage_bucket.output.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.runtime.email}"
}
resource "google_project_iam_member" "vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}
resource "google_project_iam_member" "event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.trigger.email}"
}
data "google_storage_project_service_account" "storage" {
  project    = var.project_id
  depends_on = [google_project_service.api]
}
resource "google_project_iam_member" "storage_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.storage.email_address}"
}
resource "google_cloud_run_v2_service" "worker" {
  project  = var.project_id
  name     = "signal-room-tf"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"
  template {
    service_account = google_service_account.runtime.email
    scaling { max_instance_count = 3 }
    containers {
      image = var.image
      resources { limits = { memory = "1Gi", cpu = "1" } }
      env { name = "INPUT_BUCKET" value = google_storage_bucket.input.name }
      env { name = "OUTPUT_BUCKET" value = google_storage_bucket.output.name }
      env { name = "GOOGLE_CLOUD_PROJECT" value = var.project_id }
      env { name = "MODEL" value = "gemini-2.5-flash" }
    }
    timeout = "180s"
  }
  depends_on = [google_project_service.api]
}
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.worker.location
  name     = google_cloud_run_v2_service.worker.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.trigger.email}"
}
resource "google_eventarc_trigger" "report" {
  project         = var.project_id
  name            = "signal-room-tf-finalized"
  location        = var.region
  service_account = google_service_account.trigger.email
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.input.name
  }
  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.worker.name
      region  = google_cloud_run_v2_service.worker.location
    }
  }
  depends_on = [google_project_iam_member.storage_publisher,
                google_project_iam_member.event_receiver,
                google_cloud_run_v2_service_iam_member.invoker]
}
