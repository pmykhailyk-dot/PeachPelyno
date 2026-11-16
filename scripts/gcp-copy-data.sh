#!/usr/bin/env bash
# Copy the meetings and their agendas from the API on AWS to the API on
# Google Cloud, through the two public APIs (Lab 9, Part 2, Step 2).
#
# Why not pg_dump: Aurora has no public endpoint - only the Lambda in its VPC
# reaches it - so a dump would need a bastion host. The schema on Cloud SQL
# comes from the migrations the image runs on start; the rows come through
# the same contract the frontend uses. The copies get new ids.
#
# Refuses to run against a destination that already has meetings, so a second
# run cannot duplicate everything. FORCE=1 overrides that.
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

for tool in gcloud curl jq; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
done

PROJECT_NAME="${PROJECT_NAME:-spry}"
GCP_REGION="${GCP_REGION:-us-central1}"
GCP_PROJECT="${GCP_PROJECT:-}"
SOURCE="${BACKEND_URL:-}"
[[ -n "${GCP_PROJECT}" ]] || die "GCP_PROJECT is not set in .env"
[[ -n "${SOURCE}" ]] || die "BACKEND_URL (the API on AWS) is not set in .env"
SOURCE="${SOURCE%/}"

DEST="${GCP_API_URL:-$(gcloud run services describe "${PROJECT_NAME}-api" --project "${GCP_PROJECT}" \
  --region "${GCP_REGION}" --format 'value(status.url)')}"
DEST="${DEST%/}"

# Aurora may be paused: the first call can take ~20 s.
log "reading meetings from ${SOURCE}"
MEETINGS="$(curl -fsS --max-time 90 "${SOURCE}/api/meetings")"

EXISTING="$(curl -fsS --max-time 90 "${DEST}/api/meetings" | jq length)"
if [[ "${EXISTING}" != "0" && "${FORCE:-}" != "1" ]]; then
  die "${DEST} already has ${EXISTING} meetings - FORCE=1 to copy anyway"
fi

count=0
agendas=0
while IFS= read -r meeting; do
  old_id="$(jq -r .id <<<"${meeting}")"
  new_id="$(jq '{title, starts_at, ends_at, attendee_count}' <<<"${meeting}" \
    | curl -fsS --max-time 30 -X POST -H 'Content-Type: application/json' --data @- \
      "${DEST}/api/meetings" | jq -r .id)"
  count=$((count + 1))

  agenda="$(curl -fsS --max-time 30 "${SOURCE}/api/meetings/${old_id}/agenda")"
  if [[ "${agenda}" != "null" ]]; then
    jq '{items, action_items, ai_suggestion, ai_model, ai_prompt_version}' <<<"${agenda}" \
      | curl -fsS --max-time 30 -X PUT -H 'Content-Type: application/json' --data @- \
        "${DEST}/api/meetings/${new_id}/agenda" >/dev/null
    agendas=$((agendas + 1))
  fi
done < <(jq -c '.[]' <<<"${MEETINGS}")

log "copied ${count} meetings and ${agendas} agendas to ${DEST}"
