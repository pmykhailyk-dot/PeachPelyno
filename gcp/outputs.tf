output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "api_service" {
  value = google_cloud_run_v2_service.api.name
}

output "api_url" {
  description = "The run.app URL. The site reaches the same service as /api/** on its own origin."
  value       = google_cloud_run_v2_service.api.uri
}

output "site_url" {
  value = local.site_origins[0]
}

output "registry" {
  description = "Where `make gcp-deploy-backend` pushes the image."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}"
}

output "database_instance" {
  value = google_sql_database_instance.main.name
}

output "database_connection_name" {
  value = google_sql_database_instance.main.connection_name
}
