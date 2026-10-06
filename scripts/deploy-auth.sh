#!/usr/bin/env bash
# Deploy the Cognito user pool (infra/auth.yaml): email+password sign-in plus
# "Continue with Google", behind managed login.
#
# Needs the frontend stack already deployed (its SiteUrl becomes Cognito's
# callback/logout URL) and a Google OAuth web client already created, pointed
# at this stack's Cognito domain - see README / the lab notes for the exact
# steps. Reads GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET from .env, which is
# gitignored; the secret is never written anywhere else.
#
# Writes AUTH_* into .env for deploy-frontend.sh to build the OIDC config in.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/auth.yaml"
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
STACK_NAME="${AUTH_STACK_NAME:-${PROJECT_NAME}-auth}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

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
  log "wrote ${1}=${2} to .env"
}

# --- preflight ----------------------------------------------------------

command -v aws >/dev/null 2>&1 || die "aws cli is required"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || die "no usable AWS credentials - set AWS_PROFILE or the AWS_* keys in .env"

[[ -n "${GOOGLE_CLIENT_ID:-}" ]] \
  || die "GOOGLE_CLIENT_ID is not set in .env - create the Google OAuth client first"
[[ -n "${GOOGLE_CLIENT_SECRET:-}" ]] \
  || die "GOOGLE_CLIENT_SECRET is not set in .env"

FRONTEND_STACK_NAME="${FRONTEND_STACK_NAME:-${PROJECT_NAME}-frontend}"
SITE_URL="$(aws cloudformation describe-stacks --stack-name "${FRONTEND_STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='SiteUrl'].OutputValue" --output text 2>/dev/null || true)"
[[ -n "${SITE_URL}" && "${SITE_URL}" != "None" ]] \
  || die "frontend stack ${FRONTEND_STACK_NAME} has no SiteUrl - run make deploy-frontend first"
SITE_URL="${SITE_URL%/}"

# A Cognito domain prefix is unique across every AWS account, not just this
# one. The account id makes a collision practically impossible.
DOMAIN_PREFIX="${COGNITO_DOMAIN_PREFIX:-${PROJECT_NAME}-${ACCOUNT_ID}}"

log "site ${SITE_URL}"
log "cognito domain prefix ${DOMAIN_PREFIX}"

# --- deploy ---------------------------------------------------------------

if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1; then
  log "first deploy - creating ${STACK_NAME}"
else
  log "updating ${STACK_NAME}"
fi

if ! aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "SiteUrl=${SITE_URL}" \
    "LocalOrigin=${AUTH_LOCAL_ORIGIN:-http://localhost:3000}" \
    "DomainPrefix=${DOMAIN_PREFIX}" \
    "GoogleClientId=${GOOGLE_CLIENT_ID}" \
    "GoogleClientSecret=${GOOGLE_CLIENT_SECRET}" \
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

USER_POOL_ID="$(outputs UserPoolId)"
CLIENT_ID="$(outputs UserPoolClientId)"
COGNITO_DOMAIN="$(outputs CognitoDomain)"
AUTHORITY="$(outputs Authority)"
REDIRECT_URI="$(outputs RedirectUri)"
LOGOUT_URI="$(outputs LogoutUri)"

env_set AUTH_USER_POOL_ID "${USER_POOL_ID}"
env_set AUTH_CLIENT_ID "${CLIENT_ID}"
env_set AUTH_COGNITO_DOMAIN "${COGNITO_DOMAIN}"
env_set AUTH_AUTHORITY "${AUTHORITY}"
env_set AUTH_REDIRECT_URI "${REDIRECT_URI}"
env_set AUTH_LOGOUT_URI "${LOGOUT_URI}"

echo
echo "  login page     ${SITE_URL}/login"
echo "  cognito domain  ${COGNITO_DOMAIN}"
echo "  user pool       ${USER_POOL_ID}"
echo
echo "Google console, if not done yet - Authorized JavaScript origin and"
echo "redirect URI on the OAuth client must be exactly:"
echo
echo "  ${COGNITO_DOMAIN}"
echo "  ${COGNITO_DOMAIN}/oauth2/idpresponse"
echo
echo "Next: make deploy-frontend (it builds the OIDC config from .env)."
