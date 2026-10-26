#!/usr/bin/env bash
# Run the agenda parser against pasted text, from the laptop, with no Lambda
# in the way yet (Lab 6, Part 4, Step 2).
#
#   make parse TEXT="Пн 10:00, синк по прайсингу, 45 хв. ..."
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
export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"

command -v uv >/dev/null 2>&1 || die "uv is required: https://docs.astral.sh/uv/"
[[ -n "${TEXT:-}" ]] || die 'set TEXT: make parse TEXT="Пн 10:00, синк по прайсингу..."'

(cd "${ROOT}/backend" && uv run python -m app.ai.cli parse "${TEXT}")
