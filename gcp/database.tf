# Postgres on Cloud SQL - the counterpart of Aurora Serverless v2, with one
# difference that decides the bill: it does not pause. It runs, and bills
# $0.0105 an hour, until it is stopped (`make gcp-db-stop`). Stopped, only the
# disk bills. Why this and not Firestore: docs/adr/0008-google-cloud.md.
resource "google_sql_database_instance" "main" {
  name             = "${var.project_name}-db"
  database_version = "POSTGRES_17"
  region           = var.region

  # The lab's clean-up is `terraform destroy`; this copy of the data is not
  # the only one (AWS keeps the original).
  deletion_protection = false

  settings {
    tier = var.db_tier
    # Postgres 16+ defaults to Enterprise Plus, which has no shared-core tiers:
    # without this, db-f1-micro fails at create time.
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"

    disk_type       = "PD_SSD"
    disk_size       = var.db_disk_size_gb
    disk_autoresize = false

    deletion_protection_enabled = false

    user_labels = {
      project_name = var.project_name
      managed_by   = "terraform"
    }

    # Backups bill per GB on top of the disk. AWS holds the original data.
    backup_configuration {
      enabled = false
    }

    # A public IP with no authorized networks: nothing can connect to it
    # directly. The only way in is the Cloud SQL connector Cloud Run attaches,
    # which checks IAM (roles/cloudsql.client) and encrypts the connection.
    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }
  }

  lifecycle {
    # Stopping the instance at night is an operation, not a configuration
    # change: `make gcp-db-stop` / `gcp-db-start` flip this with gcloud, and
    # the next apply must not start it again behind your back.
    ignore_changes = [settings[0].activation_policy]
  }

  depends_on = [google_project_service.this]
}

resource "google_sql_database" "app" {
  name     = var.project_name
  instance = google_sql_database_instance.main.name

  # Dropping it would fail while the API holds connections; deleting the
  # instance takes it along anyway.
  deletion_policy = "ABANDON"
}

# Letters and digits only: the password goes into a URL, and alembic's config
# parser would choke on a %.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  name     = var.project_name
  instance = google_sql_database_instance.main.name
  password = random_password.db.result

  # A Postgres role that owns tables cannot be dropped through the API.
  deletion_policy = "ABANDON"
}

# The whole connection URL, as on AWS (spry/backend/database-url): the app
# reads DATABASE_URL and nothing else. Through the connector, Postgres is a
# Unix socket under /cloudsql, which asyncpg takes as ?host=.
resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.project_name}-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret = google_secret_manager_secret.database_url.id
  secret_data = format(
    "postgresql+asyncpg://%s:%s@/%s?host=/cloudsql/%s",
    google_sql_user.app.name,
    random_password.db.result,
    google_sql_database.app.name,
    google_sql_database_instance.main.connection_name,
  )
}

# Read access for the API's account on this one secret, not on the project.
resource "google_secret_manager_secret_iam_member" "api_reads_database_url" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.api_service_account}"
}
