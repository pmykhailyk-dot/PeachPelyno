#!/usr/bin/env bash
# Copy the Terraform outputs the frontend build needs (sign-in and the agenda
# parser) into .env, for `make deploy-frontend` from a laptop. Reads the
# outputs from the HCP Terraform workspace - needs `terraform login` once.
# CI does not need this: deploy-frontend.sh looks the same values up by name.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v terraform >/dev/null 2>&1 || die "terraform is required: https://developer.hashicorp.com/terraform/install"

out() { terraform -chdir="${ROOT}/infra" output -raw "$1"; }

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

env_set AUTH_USER_POOL_ID "$(out user_pool_id)"
env_set AUTH_CLIENT_ID "$(out user_pool_client_id)"
env_set AUTH_COGNITO_DOMAIN "$(out cognito_domain)"
env_set AUTH_AUTHORITY "$(out authority)"
env_set AUTH_REDIRECT_URI "$(out redirect_uri)"
env_set AUTH_LOGOUT_URI "$(out logout_uri)"
env_set PARSER_URL "$(out parser_url)"
