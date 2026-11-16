# The counterpart of ECR. Images are tagged with the commit SHA by
# `make gcp-deploy-backend`; the first 0.5 GB stored is free.
resource "google_artifact_registry_repository" "backend" {
  repository_id = var.project_name
  location      = var.region
  format        = "DOCKER"
  description   = "Spry backend images for Cloud Run, tagged with the commit SHA."

  # Same rule as the ECR lifecycle policy: keep the last 3 images. KEEP wins
  # over DELETE, so everything else goes.
  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-last-3"
    action = "KEEP"

    most_recent_versions {
      keep_count = 3
    }
  }

  cleanup_policies {
    id     = "delete-the-rest"
    action = "DELETE"

    condition {
      tag_state = "ANY"
    }
  }

  depends_on = [google_project_service.this]
}
