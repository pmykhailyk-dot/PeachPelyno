# Bootstrap (Lab 9, Part 0): what has to exist before HCP Terraform can touch
# the Google Cloud project, so it is the one piece applied from a laptop with
# your own `gcloud auth application-default login`, and a local state:
#
#   gcloud projects create <project-id> && gcloud billing projects link ...
#   cd gcp/bootstrap && terraform init && terraform apply -var project_id=<project-id>
#
# It creates:
#   - the APIs IAM, workload identity federation and Firebase need;
#   - two service accounts, one per program: `terraform` (what HCP Terraform
#     acts as) and `spry-api` (what Cloud Run runs the API as);
#   - a workload identity pool that trusts HCP Terraform's OIDC tokens - only
#     this organization's spry-gcp workspace, matched by immutable ids;
#   - the spry-gcp workspace itself, with the env vars that switch on dynamic
#     credentials;
#   - Firebase on the project, for Hosting.
#
# No service account key is created anywhere. Like infra/bootstrap, the state
# stays on that laptop (gitignored); losing it loses nothing that cannot be
# imported back.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.80"
    }
  }
}

variable "project_id" {
  type        = string
  description = "The Google Cloud project, created beforehand with gcloud (see the README)."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "tfc_organization" {
  type    = string
  default = "ooad-pmykhailyk"
}

variable "tfc_workspace" {
  type    = string
  default = "spry-gcp"
}

variable "github_repository" {
  type        = string
  description = "owner/name - the repository the workspace reads gcp/ from."
  default     = "pmykhailyk-dot/PeachPelyno"
}

variable "github_app_installation_id" {
  type        = string
  description = "HCP Terraform's GitHub App installation, the same one spry-dev uses."
  default     = "ghain-mbCijqyJkxT6qrhK"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# The Firebase Management API refuses user credentials without a quota
# project, so this provider bills its calls to the project itself.
provider "google-beta" {
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}

# Reads the token `terraform login` stored.
provider "tfe" {
  organization = var.tfc_organization
}

data "google_project" "this" {}

data "tfe_organization" "this" {
  name = var.tfc_organization
}

# --- APIs -----------------------------------------------------------------

# The rest (Cloud Run, Cloud SQL, ...) is enabled by gcp/*.tf; these are the
# ones the bootstrap itself needs.
resource "google_project_service" "bootstrap" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

# --- service accounts -----------------------------------------------------

resource "google_service_account" "terraform" {
  account_id   = "terraform"
  display_name = "HCP Terraform, workspace ${var.tfc_workspace}"
  description  = "What gcp/*.tf is applied as. Reached through workload identity federation; has no keys."

  depends_on = [google_project_service.bootstrap]
}

resource "google_service_account" "api" {
  account_id   = "spry-api"
  display_name = "Spry API on Cloud Run"
  description  = "The identity the Cloud Run service runs as - not the default compute account, which starts with Editor."

  depends_on = [google_project_service.bootstrap]
}

# What the lab's Terraform needs, and nothing like Owner or Editor.
resource "google_project_iam_member" "terraform" {
  for_each = toset([
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/artifactregistry.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ])

  project = var.project_id
  role    = each.key
  member  = google_service_account.terraform.member
}

# Service Account User on the one account Cloud Run runs as, not on the
# project: Terraform can hand spry-api to a service, and no other account -
# itself included.
resource "google_service_account_iam_member" "terraform_acts_as_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.terraform.member
}

# Cloud SQL has no per-instance IAM, so the connector's role is project-wide.
# It lives here rather than in gcp/*.tf so that the terraform account never
# needs the right to change the project's IAM policy.
resource "google_project_iam_member" "api_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = google_service_account.api.member
}

# --- HCP Terraform workspace ----------------------------------------------

# A second workspace with its own state: a plan here cannot touch AWS, and a
# plan in spry-dev cannot touch Google Cloud. Same road as spry-dev - a pull
# request gets a speculative plan, a merge to main applies.
resource "tfe_workspace" "gcp" {
  name              = var.tfc_workspace
  organization      = var.tfc_organization
  project_id        = data.tfe_organization.this.default_project_id
  description       = "Spry's core on Google Cloud (Lab 9): Cloud Run, Cloud SQL, Artifact Registry, Secret Manager."
  working_directory = "gcp"
  auto_apply        = true
  queue_all_runs    = false

  # gcp/bootstrap/ is applied from a laptop and must not start a run.
  trigger_patterns = ["/gcp/*.tf", "/gcp/*.tfvars", "/gcp/.terraform.lock.hcl"]

  vcs_repo {
    identifier                 = var.github_repository
    github_app_installation_id = var.github_app_installation_id
  }
}

# --- workload identity federation -----------------------------------------

resource "google_iam_workload_identity_pool" "hcp" {
  workload_identity_pool_id = "hcp-terraform"
  display_name              = "HCP Terraform"
  description               = "Trusts OIDC tokens from app.terraform.io for ${var.tfc_organization}/${var.tfc_workspace}."

  depends_on = [google_project_service.bootstrap]
}

resource "google_iam_workload_identity_pool_provider" "hcp" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.hcp.workload_identity_pool_id
  workload_identity_pool_provider_id = "hcp-terraform"
  display_name                       = "app.terraform.io"

  attribute_mapping = {
    "google.subject"                      = "assertion.sub"
    "attribute.terraform_organization_id" = "assertion.terraform_organization_id"
    "attribute.terraform_workspace_id"    = "assertion.terraform_workspace_id"
    "attribute.terraform_run_phase"       = "assertion.terraform_run_phase"
  }

  # Ids, not names: an organization or workspace name can be deleted and
  # registered again by someone else, its id cannot.
  attribute_condition = join(" && ", [
    "assertion.terraform_organization_id == \"${data.tfe_organization.this.external_id}\"",
    "assertion.terraform_workspace_id == \"${tfe_workspace.gcp.id}\"",
  ])

  oidc {
    issuer_uri = "https://app.terraform.io"
  }
}

resource "google_service_account_iam_member" "hcp_impersonates_terraform" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.hcp.name}/attribute.terraform_workspace_id/${tfe_workspace.gcp.id}"
}

# Dynamic credentials: every run gets a fresh OIDC token, Google trades it
# for a short-lived token of the terraform account. Nothing secret is stored.
resource "tfe_variable" "gcp_dynamic_credentials" {
  for_each = {
    TFC_GCP_PROVIDER_AUTH             = "true"
    TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL = google_service_account.terraform.email
    TFC_GCP_WORKLOAD_PROVIDER_NAME    = google_iam_workload_identity_pool_provider.hcp.name
  }

  workspace_id = tfe_workspace.gcp.id
  category     = "env"
  key          = each.key
  value        = each.value
}

# --- Firebase -------------------------------------------------------------

# Switched on once per project. The default Hosting site (<project-id>.web.app)
# comes with it; `make gcp-deploy-frontend` deploys into it.
resource "google_firebase_project" "this" {
  provider = google-beta
  project  = var.project_id

  depends_on = [google_project_service.bootstrap]
}

output "project_number" {
  value = data.google_project.this.number
}

output "terraform_service_account" {
  value = google_service_account.terraform.email
}

output "api_service_account" {
  value = google_service_account.api.email
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.hcp.name
}

output "workspace_id" {
  value = tfe_workspace.gcp.id
}
