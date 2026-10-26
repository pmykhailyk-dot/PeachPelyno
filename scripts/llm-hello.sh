#!/usr/bin/env bash
# First call to Claude on Bedrock, from the laptop (Lab 6, Part 1, Step 1).
# Needs model access granted in Bedrock -> Model catalog (us-east-1) and
# usable AWS credentials - the same ones scripts/deploy-backend.sh reads.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"

command -v uv >/dev/null 2>&1 || { echo "uv is required: https://docs.astral.sh/uv/" >&2; exit 1; }

(cd "${ROOT}/backend" && uv run python -m app.ai.cli hello)
