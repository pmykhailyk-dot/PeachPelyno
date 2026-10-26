#!/usr/bin/env bash
# Deploy infra/ai.yml: the agenda-parser Lambda (Lab 6, Part 4).
#
# Reuses what make deploy-backend already created (the image - the parser is
# the same image, a different handler, like the Lab 5 report builder) and
# what make deploy-auth already created (the Cognito user pool the handler
# checks bearer tokens against). Run both first.
#
# Safe to re-run: the stack is the source of truth, like deploy-backend.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/ai.yml"
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
AUTH_STACK_NAME="${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"
FRONTEND_STACK_NAME="${FRONTEND_STACK_NAME:-${PROJECT_NAME}-frontend}"
STACK_NAME="${AI_STACK_NAME:-${PROJECT_NAME}-ai}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

BUDGET_EMAIL="${BUDGET_EMAIL:-${REPORT_RECIPIENT_EMAIL:-${REPORT_EMAIL:-}}}"
[[ -n "${BUDGET_EMAIL}" ]] || die "set BUDGET_EMAIL (or REPORT_RECIPIENT_EMAIL / REPORT_EMAIL) in .env - where the \$5 cost alert goes"

for tool in aws python3; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || die "no usable AWS credentials - set AWS_PROFILE or the AWS_* keys in .env"
log "account ${ACCOUNT_ID} in ${AWS_REGION}"

# --- reuse the backend stack (image) ----------------------------------------

aws cloudformation describe-stacks --stack-name "${BACKEND_STACK_NAME}" >/dev/null 2>&1 \
  || die "stack ${BACKEND_STACK_NAME} does not exist - run make deploy-backend first"

backend_function="$(aws cloudformation describe-stacks --stack-name "${BACKEND_STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='FunctionName'].OutputValue" --output text)"
IMAGE_URI="$(aws lambda get-function --function-name "${backend_function}" \
  --query 'Code.ImageUri' --output text)"
log "reusing backend image ${IMAGE_URI}"

# --- reuse the auth stack (user pool) ---------------------------------------

AUTH_USER_POOL_ID="${AUTH_USER_POOL_ID:-}"
AUTH_CLIENT_ID="${AUTH_CLIENT_ID:-}"
if [[ -z "${AUTH_USER_POOL_ID}" || -z "${AUTH_CLIENT_ID}" ]]; then
  aws cloudformation describe-stacks --stack-name "${AUTH_STACK_NAME}" >/dev/null 2>&1 \
    || die "AUTH_USER_POOL_ID/AUTH_CLIENT_ID not set and stack ${AUTH_STACK_NAME} does not exist - run make deploy-auth first"
  AUTH_USER_POOL_ID="$(aws cloudformation describe-stacks --stack-name "${AUTH_STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)"
  AUTH_CLIENT_ID="$(aws cloudformation describe-stacks --stack-name "${AUTH_STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text)"
fi
log "checking tokens against user pool ${AUTH_USER_POOL_ID}"

# --- who may call it ---------------------------------------------------------

SITE_URL="$(aws cloudformation describe-stacks --stack-name "${FRONTEND_STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='SiteUrl'].OutputValue" --output text 2>/dev/null || true)"
[[ "${SITE_URL}" == "None" ]] && SITE_URL=""
CORS_ORIGINS="http://localhost:3000"
if [[ -n "${SITE_URL}" ]]; then
  CORS_ORIGINS="${CORS_ORIGINS},${SITE_URL}"
else
  warn "stack ${FRONTEND_STACK_NAME} not found - CORS allows only http://localhost:3000 for now; re-run after make deploy-frontend"
fi

# --- deploy -------------------------------------------------------------

PARAMS_FILE="$(mktemp)"
chmod 600 "${PARAMS_FILE}"
trap 'rm -f "${PARAMS_FILE}"' EXIT

PROJECT_NAME="${PROJECT_NAME}" \
IMAGE_URI="${IMAGE_URI}" \
ARCHITECTURE="${LAMBDA_ARCHITECTURE:-arm64}" \
PARSER_MODEL="${PARSER_MODEL:-}" \
CORS_ORIGINS="${CORS_ORIGINS}" \
AUTH_USER_POOL_ID="${AUTH_USER_POOL_ID}" \
AUTH_CLIENT_ID="${AUTH_CLIENT_ID}" \
BUDGET_AMOUNT="${BUDGET_AMOUNT:-}" \
BUDGET_EMAIL="${BUDGET_EMAIL}" \
python3 - "${PARAMS_FILE}" <<'PY'
import json, os, sys

arch = {"arm64": "arm64", "amd64": "x86_64"}.get(os.environ["ARCHITECTURE"], os.environ["ARCHITECTURE"])
params = {
    "ProjectName": os.environ["PROJECT_NAME"],
    "ImageUri": os.environ["IMAGE_URI"],
    "Architecture": arch,
    "ParserModel": os.environ["PARSER_MODEL"],
    "CorsOrigins": os.environ["CORS_ORIGINS"],
    "AuthUserPoolId": os.environ["AUTH_USER_POOL_ID"],
    "AuthClientId": os.environ["AUTH_CLIENT_ID"],
    "BudgetAmount": os.environ["BUDGET_AMOUNT"],
    "BudgetEmail": os.environ["BUDGET_EMAIL"],
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

PARSER_URL="$(outputs ParserUrl)"

# env_set mirrors deploy-backend.sh's helper: rewrite one KEY=VALUE in .env,
# leaving everything else untouched.
env_set() {
  KEY="$1" VALUE="$2" ENV_FILE="${ENV_FILE}" python3 - <<'PY'
import os, re

key, value, path = os.environ["KEY"], os.environ["VALUE"], os.environ["ENV_FILE"]
lines = open(path).read().splitlines() if os.path.exists(path) else []
pattern = re.compile(rf"^{re.escape(key)}=")
for i, line in enumerate(lines):
    if pattern.match(line):
        lines[i] = f"{key}={value}"
        break
else:
    lines.append(f"{key}={value}")
open(path, "w").write("\n".join(lines) + "\n")
PY
}
env_set PARSER_URL "${PARSER_URL}"

echo
echo "  parser url   ${PARSER_URL}"
echo "  logs         aws logs tail $(outputs LogGroupName) --follow"
echo "  CORS origins ${CORS_ORIGINS}"
echo
echo "Next: make deploy-frontend (builds the Paste an agenda screen against PARSER_URL)."
