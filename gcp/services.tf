# APIs are off in a fresh project. Enabling them here, rather than in the
# console, is what makes a new project reproducible from this folder. The
# ones IAM and federation need are enabled by gcp/bootstrap/.
resource "google_project_service" "this" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
  ])

  service = each.key
  # An enabled API costs nothing, and switching one off under a running
  # service is how a destroy gets stuck half way.
  disable_on_destroy = false
}
