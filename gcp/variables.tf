variable "project_name" {
  type        = string
  description = "Prefix of every resource name, and the project_name label."
  default     = "spry"
}

variable "project_id" {
  type        = string
  description = "The Google Cloud project, created by hand once (README) - its id can never be reused."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "api_service_account_id" {
  type        = string
  description = "The account Cloud Run runs the API as. Created by gcp/bootstrap/, with roles/cloudsql.client."
  default     = "spry-api"
}

# --- database -------------------------------------------------------------

variable "db_tier" {
  type        = string
  description = "db-f1-micro: shared core, 0.6 GB, $0.0105/h. Bills every hour it runs - it does not pause."
  default     = "db-f1-micro"
}

variable "db_disk_size_gb" {
  type    = number
  default = 10
}

# --- API ------------------------------------------------------------------

variable "api_max_instances" {
  type        = number
  description = <<-EOT
    The ceiling on what a traffic spike can cost. One instance serves 80
    requests at a time, and its connection pool (5 + 10 overflow) fits the
    25 connections db-f1-micro allows; two would not, under load.
  EOT
  default     = 1
}

variable "api_memory" {
  type    = string
  default = "512Mi"
}
