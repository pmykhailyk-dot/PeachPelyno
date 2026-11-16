#!/usr/bin/env bash
# Build the backend image for Cloud Run, push it to Artifact Registry and roll
# the spry-api service onto it (Lab 9). gcp/*.tf owns the service - its
# account, the Cloud SQL connection, the secret, the scaling - and leaves the
# image to this script, the same split as the Lambda image on AWS.
#
# Migrations need no separate step: the image's entrypoint runs
# `alembic upgrade head` before uvicorn starts, and Cloud Run starts one
# instance of every new revision before it sends it traffic.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ENV_FILE}" ]]; then
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ENV_FILE}"
  set +a
  eval "${preset}"
fi

PROJECT_NAME="${PROJECT_NAME:-spry}"
GCP_REGION="${GCP_REGION:-us-central1}"
GCP_PROJECT="${GCP_PROJECT:-}"
SERVICE="${PROJECT_NAME}-api"

for tool in gcloud docker curl; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
done
docker info >/dev/null 2>&1 || die "docker daemon is not running"
[[ -n "${GCP_PROJECT}" ]] || die "GCP_PROJECT is not set in .env"
gcloud auth print-access-token >/dev/null 2>&1 || die "no gcloud login - run: gcloud auth login"

gcloud run services describe "${SERVICE}" --project "${GCP_PROJECT}" --region "${GCP_REGION}" \
  --format 'value(metadata.name)' >/dev/null 2>&1 \
  || die "no Cloud Run service ${SERVICE} - gcp/*.tf has to be applied first"

# --- image ------------------------------------------------------------------

REGISTRY="${GCP_REGION}-docker.pkg.dev"
REPOSITORY="${REGISTRY}/${GCP_PROJECT}/${PROJECT_NAME}"

if [[ -z "${IMAGE_TAG:-}" || "${IMAGE_TAG}" == "latest" ]]; then
  IMAGE_TAG="$(git -C "${ROOT}" rev-parse --short=12 HEAD)"
  # A dirty tree gets a unique tag, so a rebuild is never mistaken for the
  # commit it was built on.
  git -C "${ROOT}" diff --quiet HEAD -- backend \
    || IMAGE_TAG="${IMAGE_TAG}-dirty-$(date -u +%Y%m%d%H%M%S)"
fi
IMAGE_URI="${REPOSITORY}/backend:${IMAGE_TAG}"

# A one-hour token, not `gcloud auth configure-docker`: nothing long-lived
# lands in Docker's config.
gcloud auth print-access-token \
  | docker login --username oauth2accesstoken --password-stdin "https://${REGISTRY}" >/dev/null

# Cloud Run is x86_64 only, so on Apple Silicon this builds under emulation.
# The runtime target is the one Compose runs: uvicorn, no Lambda adapter.
log "building ${IMAGE_URI} for linux/amd64"
docker buildx build \
  --platform linux/amd64 \
  --target runtime \
  --provenance=false \
  --sbom=false \
  --tag "${IMAGE_URI}" \
  --push \
  "${ROOT}/backend"

# --- roll -------------------------------------------------------------------

log "rolling ${SERVICE} onto ${IMAGE_TAG}"
gcloud run services update "${SERVICE}" \
  --project "${GCP_PROJECT}" \
  --region "${GCP_REGION}" \
  --image "${IMAGE_URI}" \
  --quiet

API_URL="$(gcloud run services describe "${SERVICE}" --project "${GCP_PROJECT}" \
  --region "${GCP_REGION}" --format 'value(status.url)')"

log "checking ${API_URL}/api/health/ready"
curl -fsS --max-time 60 "${API_URL}/api/health/ready" && echo

echo
echo "  api     ${API_URL}"
echo "  image   ${IMAGE_URI}"
echo
