variable "project_name" {
  type        = string
  description = "Prefix of every resource name, and the PROJECT_NAME tag."
  default     = "spry"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "lambda_architecture" {
  type        = string
  description = "Must match the backend image's platform - the builder and the parser reuse it."
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.lambda_architecture)
    error_message = "lambda_architecture must be arm64 or x86_64."
  }
}

variable "log_retention_days" {
  type    = number
  default = 7
}

# --- auth (Lab 4) ---------------------------------------------------------

variable "local_origin" {
  type        = string
  description = "Dev server origin, so sign-in also works from `pnpm dev`."
  default     = "http://localhost:3000"
}

variable "google_client_id" {
  type        = string
  description = "OAuth client ID from Google Cloud Console (Web application). Not a secret."
}

variable "google_client_secret" {
  type        = string
  description = "OAuth client secret from the same Google client. Set in the HCP Terraform workspace, never in a file."
  sensitive   = true
}

# --- weekly report (Lab 5) ------------------------------------------------

variable "report_sender_email" {
  type        = string
  description = "The From address. In the SES sandbox it has to be verified, like the recipient."
}

variable "report_recipient_email" {
  type        = string
  description = "Where the weekly report is sent."
}

variable "report_schedule_expression" {
  type    = string
  default = "cron(0 7 ? * MON *)"
}

variable "report_schedule_timezone" {
  type    = string
  default = "Europe/Kyiv"
}

variable "builder_memory_size" {
  type    = number
  default = 512
}

variable "builder_timeout_seconds" {
  type        = number
  description = "Leaves room for Aurora to resume from a pause (about 15 seconds)."
  default     = 60
}

variable "queue_visibility_timeout_seconds" {
  type        = number
  description = "At least 6x builder_timeout_seconds, or a second builder can start on the same message."
  default     = 360

  validation {
    condition     = var.queue_visibility_timeout_seconds >= 6 * var.builder_timeout_seconds
    error_message = "queue_visibility_timeout_seconds must be at least 6x builder_timeout_seconds."
  }
}

# --- agenda parser (Lab 6) ------------------------------------------------

variable "parser_model" {
  type        = string
  description = "Bedrock model id - change it to compare models (Lab 6, Part 4, Step 5)."
  default     = "us.anthropic.claude-opus-4-5-20251101-v1:0"
}

variable "parser_memory_size" {
  type    = number
  default = 512
}

variable "parser_timeout_seconds" {
  type    = number
  default = 30
}

variable "budget_amount" {
  type        = number
  description = "Monthly USD threshold for the agenda parser's cost alert."
  default     = 5
}

variable "budget_email" {
  type        = string
  description = "Where AWS Budgets sends the alert."
}
