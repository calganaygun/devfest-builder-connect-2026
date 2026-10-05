output "input_bucket" { value = google_storage_bucket.input.name }
output "output_bucket" { value = google_storage_bucket.output.name }
output "service_url" { value = google_cloud_run_v2_service.worker.uri }
