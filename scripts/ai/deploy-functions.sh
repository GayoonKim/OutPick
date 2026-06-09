#!/usr/bin/env bash

set -euo pipefail

PROJECT_ID="${OUTPICK_FIREBASE_PROJECT_ID:-outpick-664ae}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FUNCTIONS_DIR="$ROOT_DIR/functions"

usage() {
  cat <<'EOF'
Usage:
  scripts/ai/deploy-functions.sh functionName [functionName ...]

Examples:
  scripts/ai/deploy-functions.sh requestSeasonCandidateImportsAndProcess
  scripts/ai/deploy-functions.sh requestSeasonImport requestSeasonAssetRetry

Environment:
  OUTPICK_FIREBASE_PROJECT_ID  Firebase project ID. Defaults to outpick-664ae.

The script always runs functions lint/build before deploy.
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

for name in "$@"; do
  if [[ ! "$name" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "Invalid function name: $name" >&2
    exit 2
  fi
done

deploy_targets=""
for name in "$@"; do
  if [[ -z "$deploy_targets" ]]; then
    deploy_targets="functions:$name"
  else
    deploy_targets="$deploy_targets,functions:$name"
  fi
done

(
  cd "$FUNCTIONS_DIR"
  npm run lint
  npm run build
)

firebase deploy --only "$deploy_targets" --project "$PROJECT_ID"
