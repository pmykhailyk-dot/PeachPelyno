# Terraform for the parts of Spry that Labs 4-6 built: sign-in (auth.tf),
# the weekly report (reports.tf) and the agenda parser (ai.tf). One root
# module, one HCP Terraform workspace, applied by HCP Terraform after a merge
# to main - never from a laptop (docs/adr/0007-terraform.md).
#
# The older stacks - backend (API + Aurora), frontend (S3 + CloudFront) and
# the GitHub OIDC role - stay CloudFormation for now; data.tf reads their
# outputs.

terraform {
  required_version = ">= 1.10"

  cloud {
    organization = "ooad-pmykhailyk"

    workspaces {
      name = "spry-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.region

  # PROJECT_NAME on every resource that takes tags (Lab 4's rule), without
  # repeating it in every resource block. ManagedBy tells whoever finds a
  # resource in the console not to edit it there: the next apply undoes it.
  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
      ManagedBy    = "terraform"
    }
  }
}
