# Terraform for Spry's core on Google Cloud (Lab 9): the API on Cloud Run,
# Postgres on Cloud SQL, the image registry and the database secret. Its own
# HCP Terraform workspace (spry-gcp) and its own state, apart from infra/ -
# one plan cannot break both clouds (docs/adr/0008-google-cloud.md).
#
# HCP Terraform reaches the project through workload identity federation:
# the TFC_GCP_* env vars on the workspace, set by gcp/bootstrap/. No key.

terraform {
  required_version = ">= 1.10"

  cloud {
    organization = "ooad-pmykhailyk"

    workspaces {
      name = "spry-gcp"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # The GCP counterpart of infra/'s default_tags. Label keys are lowercase.
  default_labels = {
    project_name = var.project_name
    managed_by   = "terraform"
  }
}
