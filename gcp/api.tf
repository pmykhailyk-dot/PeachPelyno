# The API on Cloud Run - the counterpart of Lambda + function URL. The same
# image runs on a laptop (`docker compose up`): uvicorn on $PORT, no Mangum,
# no 15-minute limit. Scales to zero, so idle it costs nothing.

locals {
  api_service_account = "${var.api_service_account_id}@${var.project_id}.iam.gserviceaccount.com"

  # Firebase Hosting's default site. The browser normally calls the API
  # through the site's /api/** rewrite (one origin, no CORS); these let it
  # call the run.app URL directly too.
  site_origins = [
    "https://${var.project_id}.web.app",
    "https://${var.project_id}.firebaseapp.com",
  ]
}

resource "google_cloud_run_v2_service" "api" {
  name     = "${var.project_name}-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = false

  template {
    service_account                  = local.api_service_account
    max_instance_request_concurrency = 80
    timeout                          = "60s"

    scaling {
      min_instance_count = 0
      max_instance_count = var.api_max_instances
    }

    volumes {
      name = "cloudsql"

      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      # A placeholder for the very first apply, before any image is pushed.
      # From then on `make gcp-deploy-backend` rolls the image, not Terraform
      # (the same split as the Lambda image on AWS).
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      resources {
        limits = {
          cpu    = "1"
          memory = var.api_memory
        }
        # Request-based billing: CPU only while a request is being served.
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "APP_ENV"
        value = "production"
      }
      env {
        name  = "LOG_LEVEL"
        value = "info"
      }
      env {
        name  = "CORS_ORIGINS"
        value = join(",", local.site_origins)
      }
      # Cloud Run's front end terminates TLS; trust its X-Forwarded-* so
      # redirects say https.
      env {
        name  = "FORWARDED_ALLOW_IPS"
        value = "*"
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  # Cloud Run checks at deploy time that the account can read the secret.
  depends_on = [
    google_secret_manager_secret_iam_member.api_reads_database_url,
    google_secret_manager_secret_version.database_url,
  ]
}

# Public, as the Lambda function URL is (AuthType NONE): the meetings
# endpoints have no sign-in on AWS either, and Firebase Hosting's rewrite
# reaches Cloud Run as an anonymous caller. See the ADR.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
