#!/usr/bin/env bash
# Build the Next.js static export and deploy it to Firebase Hosting (Lab 9).
#
# The bundle calls the API on its own origin: frontend/firebase.json rewrites
# /api/** to the spry-api Cloud Run service, so NEXT_PUBLIC_API_URL is empty
# and there is no CORS - what CloudFront's /api behaviour would give on AWS.
#
# Sign-in and Paste an agenda stay on AWS and are built switched off here:
# Cognito only knows the CloudFront site's callback URL, and the parser's
# function URL only lets that origin through.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT}/frontend"
ENV_FILE="${ROOT}/.env"
# Pinned: `npx firebase-tools` alone would pick up whatever was published today.
FIREBASE_TOOLS="${FIREBASE_TOOLS:-firebase-tools@15.34.2}"

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

GCP_PROJECT="${GCP_PROJECT:-}"
[[ -n "${GCP_PROJECT}" ]] || die "GCP_PROJECT is not set in .env"
command -v node >/dev/null 2>&1 || die "node is required but not installed"

if command -v pnpm >/dev/null 2>&1; then
  PM=(pnpm)
elif command -v corepack >/dev/null 2>&1; then
  PM=(corepack pnpm)
else
  PM=(npx --yes pnpm@10)
fi

# --- build ------------------------------------------------------------------

log "installing dependencies"
(cd "${APP}" && "${PM[@]}" install --frozen-lockfile)

log "building the static export (API on the same origin, sign-in off)"
rm -rf "${APP}/out"
(cd "${APP}" && NEXT_OUTPUT=export \
  NEXT_PUBLIC_API_URL="" \
  NEXT_PUBLIC_COGNITO_AUTHORITY="" \
  NEXT_PUBLIC_COGNITO_CLIENT_ID="" \
  NEXT_PUBLIC_COGNITO_REDIRECT_URI="" \
  NEXT_PUBLIC_COGNITO_DOMAIN="" \
  NEXT_PUBLIC_COGNITO_LOGOUT_URI="" \
  NEXT_PUBLIC_PARSER_URL="" \
  "${PM[@]}" build)
[[ -f "${APP}/out/index.html" ]] || die "the export produced no out/index.html"

# --- deploy -----------------------------------------------------------------

# firebase-tools signs in with your gcloud application default credentials
# (gcloud auth application-default login) - no `firebase login`, no token.
log "deploying to Firebase Hosting (${GCP_PROJECT})"
(cd "${APP}" && npx --yes "${FIREBASE_TOOLS}" deploy \
  --only hosting \
  --project "${GCP_PROJECT}" \
  --non-interactive)

echo
echo "  site    https://${GCP_PROJECT}.web.app"
echo "  api     https://${GCP_PROJECT}.web.app/api/meetings"
echo
