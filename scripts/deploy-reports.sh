#!/usr/bin/env bash
# Deploy infra/reports.yml: the weekly meetings report (Lab 5).
#
# Reuses what `make deploy-backend` already created instead of asking for it
# again: the backend Lambda's image (the builder runs the same image, just a
# different handler - see app/reports/lambda_handler.py), its VPC subnets and
# security group (already allowed into Aurora's security group, so the
# builder needs no new one), and the database URL from its secret.
#
# Safe to re-run: like deploy-backend.sh, the stack is the source of truth.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/reports.yml"
MAILER_SOURCE_FILE="${ROOT}/infra/lambda/report_mailer.py"
ENV_FILE="${ROOT}/.env"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
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
BACKEND_STACK_NAME="${STACK_NAME:-${PROJECT_NAME}-backend}"
STACK_NAME="${REPORTS_STACK_NAME:-${PROJECT_NAME}-reports}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

REPORT_SENDER_EMAIL="${REPORT_SENDER_EMAIL:-${REPORT_EMAIL:-}}"
REPORT_RECIPIENT_EMAIL="${REPORT_RECIPIENT_EMAIL:-${REPORT_EMAIL:-}}"
[[ -n "${REPORT_SENDER_EMAIL}" && -n "${REPORT_RECIPIENT_EMAIL}" ]] \
  || die "set REPORT_EMAIL (or REPORT_SENDER_EMAIL / REPORT_RECIPIENT_EMAIL) in .env"

for tool in aws python3; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || die "no usable AWS credentials - set AWS_PROFILE or the AWS_* keys in .env"
log "account ${ACCOUNT_ID} in ${AWS_REGION}"

# --- reuse the backend stack -------------------------------------------------

aws cloudformation describe-stacks --stack-name "${BACKEND_STACK_NAME}" >/dev/null 2>&1 \
  || die "stack ${BACKEND_STACK_NAME} does not exist - run make deploy-backend first"

backend_output() {
  aws cloudformation describe-stacks --stack-name "${BACKEND_STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

BACKEND_FUNCTION_NAME="$(backend_output FunctionName)"
IMAGE_URI="$(aws lambda get-function --function-name "${BACKEND_FUNCTION_NAME}" \
  --query 'Code.ImageUri' --output text)"

read -r VPC_ID SUBNET_IDS SECURITY_GROUP_ID <<<"$(aws lambda get-function-configuration \
  --function-name "${BACKEND_FUNCTION_NAME}" --query 'VpcConfig' --output json \
  | python3 -c '
import json, sys
cfg = json.load(sys.stdin)
print(cfg["VpcId"], ",".join(cfg["SubnetIds"]), cfg["SecurityGroupIds"][0])
')"

SECRET_ARN="$(backend_output DatabaseUrlSecretArn)"
DATABASE_URL="$(aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" \
  --query SecretString --output text)"

ROUTE_TABLE_ID="$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.main,Values=true" \
  --query 'RouteTables[0].RouteTableId' --output text)"
[[ -n "${ROUTE_TABLE_ID}" && "${ROUTE_TABLE_ID}" != "None" ]] \
  || die "could not find the main route table of ${VPC_ID} - set it explicitly if your VPC uses per-subnet route tables"

log "reusing backend image ${IMAGE_URI}"
log "VPC ${VPC_ID}, subnets ${SUBNET_IDS}, security group ${SECURITY_GROUP_ID}, route table ${ROUTE_TABLE_ID}"

# --- deploy -------------------------------------------------------------

PARAMS_FILE="$(mktemp)"
chmod 600 "${PARAMS_FILE}"
trap 'rm -f "${PARAMS_FILE}"' EXIT

PROJECT_NAME="${PROJECT_NAME}" \
VPC_ID="${VPC_ID}" \
SUBNET_IDS="${SUBNET_IDS}" \
SECURITY_GROUP_ID="${SECURITY_GROUP_ID}" \
ROUTE_TABLE_ID="${ROUTE_TABLE_ID}" \
IMAGE_URI="${IMAGE_URI}" \
DATABASE_URL="${DATABASE_URL}" \
REPORT_SENDER_EMAIL="${REPORT_SENDER_EMAIL}" \
REPORT_RECIPIENT_EMAIL="${REPORT_RECIPIENT_EMAIL}" \
MAILER_SOURCE="$(cat "${MAILER_SOURCE_FILE}")" \
SCHEDULE_EXPRESSION="${REPORT_SCHEDULE_EXPRESSION:-}" \
SCHEDULE_TIMEZONE="${REPORT_SCHEDULE_TIMEZONE:-}" \
python3 - "${PARAMS_FILE}" <<'PY'
import json, os, sys

params = {
    "ProjectName": os.environ["PROJECT_NAME"],
    "VpcId": os.environ["VPC_ID"],
    "SubnetIds": os.environ["SUBNET_IDS"],
    "SecurityGroupId": os.environ["SECURITY_GROUP_ID"],
    "RouteTableId": os.environ["ROUTE_TABLE_ID"],
    "ImageUri": os.environ["IMAGE_URI"],
    "DatabaseUrl": os.environ["DATABASE_URL"],
    "ReportSenderEmail": os.environ["REPORT_SENDER_EMAIL"],
    "ReportRecipientEmail": os.environ["REPORT_RECIPIENT_EMAIL"],
    "MailerSource": os.environ["MAILER_SOURCE"],
    "ScheduleExpression": os.environ["SCHEDULE_EXPRESSION"],
    "ScheduleTimezone": os.environ["SCHEDULE_TIMEZONE"],
}
with open(sys.argv[1], "w") as fh:
    json.dump(
        [{"ParameterKey": k, "ParameterValue": v} for k, v in params.items() if v != ""],
        fh,
    )
PY

if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1; then
  log "first deploy - creating ${STACK_NAME}"
else
  log "updating ${STACK_NAME}"
fi

if ! aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides "file://${PARAMS_FILE}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  warn "deploy failed - most recent failure reasons:"
  aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" \
    --max-items 40 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
  exit 1
fi

outputs() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

echo
echo "  bucket       s3://$(outputs ReportsBucketName)/reports/"
echo "  queue        $(outputs ReportRequestsQueueUrl)"
echo "  dlq          $(outputs ReportRequestsDlqUrl)"
echo "  builder logs aws logs tail $(outputs BuilderLogGroupName) --follow"
echo "  mailer logs  aws logs tail $(outputs MailerLogGroupName) --follow"
echo

if aws sesv2 get-email-identity --email-identity "${REPORT_SENDER_EMAIL}" \
    --query 'VerifiedForSendingStatus' --output text 2>/dev/null | grep -qi true; then
  log "SES identity ${REPORT_SENDER_EMAIL} is verified"
else
  warn "SES identity ${REPORT_SENDER_EMAIL} is not verified yet - check its inbox for AWS's verification email and click the link, then re-run make report-now"
fi

echo "Next: make report-now WEEK=$(date -u -d 'last monday - 7 days' +%G-W%V 2>/dev/null || date -u -v-mon -v-7d +%G-W%V)"
