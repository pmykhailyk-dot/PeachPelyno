#!/usr/bin/env bash
# Send one report-request message to the queue by hand: the on-demand trigger
# from Lab 5, Step 4 - the same entry point the weekly schedule uses, so the
# builder cannot tell the two apart except by the "source" field.
#
#   make report-now                     # last ISO week, decided by the builder
#   make report-now WEEK=2026-W39       # rebuild a specific week
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

for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-spry}"
STACK_NAME="${REPORTS_STACK_NAME:-${PROJECT_NAME}-reports}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

QUEUE_URL="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='ReportRequestsQueueUrl'].OutputValue" --output text 2>/dev/null)"
[[ -n "${QUEUE_URL}" && "${QUEUE_URL}" != "None" ]] \
  || die "stack ${STACK_NAME} has no ReportRequestsQueueUrl output - run make deploy-reports first"

BODY="$(WEEK="${WEEK:-}" python3 -c '
import json, os
week = os.environ.get("WEEK") or None
print(json.dumps({"source": "manual", "week": week}))
')"

log "sending ${BODY} to ${QUEUE_URL}"
aws sqs send-message --queue-url "${QUEUE_URL}" --message-body "${BODY}" >/dev/null
log "sent - watch it land: make logs-report-builder"
