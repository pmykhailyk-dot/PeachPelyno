# Bootstrap (Lab 7, Part 1, Step 7): the IAM OIDC provider and role that let
# HCP Terraform reach AWS with no stored keys. It has to exist before HCP
# Terraform can do anything, so it is the one piece applied from a laptop,
# with a local state:
#
#   cd infra/bootstrap && terraform init && terraform apply \
#     -var tfc_organization=<org>
#
# The state stays on that laptop (gitignored). Losing it loses nothing that
# matters: `terraform import` both resources back, or re-create the role.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      PROJECT_NAME = "spry"
      ManagedBy    = "terraform-bootstrap"
    }
  }
}

variable "tfc_organization" {
  type        = string
  description = "HCP Terraform organization that may assume the role."
}

variable "tfc_workspaces" {
  type        = list(string)
  description = "Workspaces of that organization allowed to assume the role - not every workspace of it."
  default     = ["spry-dev"]
}

data "tls_certificate" "tfc" {
  url = "https://app.terraform.io"
}

resource "aws_iam_openid_connect_provider" "tfc" {
  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = [data.tls_certificate.tfc.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "tfc" {
  name = "hcp-terraform-${var.tfc_organization}"

  # Narrower than the lab's "any workspace of the organization": only the
  # workspaces listed above, in any project, in both run phases.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.tfc.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "app.terraform.io:aud" = "aws.workload.identity" }
        StringLike = {
          "app.terraform.io:sub" = [
            for ws in var.tfc_workspaces :
            "organization:${var.tfc_organization}:project:*:workspace:${ws}:run_phase:*"
          ]
        }
      }
    }]
  })
}

# For the class project. A real team narrows this to the services the
# workspace manages (Cognito, Lambda, IAM on these roles, S3, SQS, ...).
resource "aws_iam_role_policy_attachment" "tfc" {
  role       = aws_iam_role.tfc.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "role_arn" {
  value = aws_iam_role.tfc.arn
}
