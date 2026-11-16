#!/usr/bin/env bash
# Stop or start the Cloud SQL instance: make gcp-db-stop / make gcp-db-start.
#
# Cloud SQL does not pause on idle the way Aurora does. Running, db-f1-micro
# bills $0.0105 an hour (~$7.70 a month); stopped, only its 10 GB disk bills
# (~$1.70 a month) and the API answers 503 on anything that reads the
# database. gcp/database.tf ignores the activation policy, so an apply does
# not undo this.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ENV_FILE}" ]]; then
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ENV_FILE}"
  set +a
  eval "${preset}"
fi

GCP_PROJECT="${GCP_PROJECT:-}"
INSTANCE="${PROJECT_NAME:-spry}-db"
[[ -n "${GCP_PROJECT}" ]] || die "GCP_PROJECT is not set in .env"

case "${1:-}" in
  stop) policy=NEVER ;;
  start) policy=ALWAYS ;;
  *) die "usage: $0 stop|start" ;;
esac

gcloud sql instances patch "${INSTANCE}" --project "${GCP_PROJECT}" \
  --activation-policy "${policy}" --quiet
gcloud sql instances describe "${INSTANCE}" --project "${GCP_PROJECT}" \
  --format 'table(name, state, settings.activationPolicy, settings.tier)'
