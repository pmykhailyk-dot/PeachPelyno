#!/usr/bin/env bash
# Tear the reports stack down: the two Lambdas, the queue and its DLQ, the
# schedule, and the reports bucket. Touches nothing in the backend stack -
# that image, VPC, security group and database are only borrowed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ROOT}/.env" ]]; then
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
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

command -v aws >/dev/null 2>&1 || die "aws cli is required"
aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1 \
  || die "stack ${STACK_NAME} does not exist in ${AWS_REGION}"

if [[ "${FORCE:-0}" != "1" ]]; then
  echo "This deletes stack ${STACK_NAME} in ${AWS_REGION}, including every report in"
  echo "the ${PROJECT_NAME}-reports-* bucket."
  read -r -p "Type the stack name to confirm: " reply
  [[ "${reply}" == "${STACK_NAME}" ]] || die "aborted"
fi

BUCKET="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='ReportsBucketName'].OutputValue" --output text 2>/dev/null || true)"

# CloudFormation can only delete an empty bucket.
if [[ -n "${BUCKET}" && "${BUCKET}" != "None" ]]; then
  log "emptying s3://${BUCKET}"
  aws s3 rm "s3://${BUCKET}" --recursive >/dev/null
fi

log "deleting ${STACK_NAME} (a few minutes)"
aws cloudformation delete-stack --stack-name "${STACK_NAME}"
aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"

log "done - nothing from this stack is still billing"
