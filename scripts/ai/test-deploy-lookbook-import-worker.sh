#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_SCRIPT="$ROOT_DIR/scripts/ai/deploy-lookbook-import-worker.sh"
WORKER_DIR="$ROOT_DIR/tools/lookbook-import-worker"
TEMPORARY_DIRECTORY="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMPORARY_DIRECTORY"
}
trap cleanup EXIT

development_plan="$TEMPORARY_DIRECTORY/development-plan.txt"
production_plan="$TEMPORARY_DIRECTORY/production-plan.txt"

"$DEPLOY_SCRIPT" development --plan >"$development_plan"
"$DEPLOY_SCRIPT" production --plan >"$production_plan"

plan_value() {
  local plan_path="$1"
  local key="$2"
  sed -n "s/^${key}=//p" "$plan_path"
}

validate_plan_with_worker_config() {
  local plan_path="$1"
  (
    cd "$WORKER_DIR"
    OUTPICK_FIREBASE_PROJECT_ID="$(plan_value "$plan_path" project)" \
    OUTPICK_FIREBASE_STORAGE_BUCKET="$(plan_value "$plan_path" storage_bucket)" \
    OUTPICK_IMPORT_OIDC_AUDIENCE="$(plan_value "$plan_path" oidc_audience)" \
    OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL="$(plan_value "$plan_path" task_service_account)" \
    OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL="$(plan_value "$plan_path" functions_service_account)" \
    K_REVISION="lookbook-import-worker-contract-test" \
    OUTPICK_WORKER_SOURCE_REVISION="$(plan_value "$plan_path" source_revision)" \
    OUTPICK_SEASON_DISCOVERY_CONTRACT_REVISION="$(plan_value "$plan_path" season_discovery_contract_revision)" \
    OUTPICK_SEASON_DISCOVERY_EXTRACTOR_VERSION="$(plan_value "$plan_path" season_discovery_extractor_version)" \
    node --input-type=module -e \
      'import {loadConfig} from "./lib/config.js"; loadConfig(process.env);'
  )
}

(
  cd "$WORKER_DIR"
  npm run build >/dev/null
)
validate_plan_with_worker_config "$development_plan"
validate_plan_with_worker_config "$production_plan"

grep -Fq "project=outpick-test" "$development_plan"
grep -Fq "service=lookbook-import-worker-development" "$development_plan"
grep -Fq "storage_bucket=outpick-test.firebasestorage.app" "$development_plan"
grep -Fq "oidc_audience=https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app" "$development_plan"
grep -Fq "task_service_account=outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com" "$development_plan"
development_service_name="$(plan_value "$development_plan" service)"
development_tag="$(plan_value "$development_plan" candidate_tag)"
[[ "$development_tag" =~ ^c[0-9]{10}$ ]]
if (( ${#development_tag} + ${#development_service_name} + 1 > 46 )); then
  echo "Development candidate tag와 service명 결합 길이가 46자를 초과합니다." >&2
  exit 1
fi
grep -Fq "functions_service_account=86635107099-compute@developer.gserviceaccount.com" "$development_plan"
grep -Fq "season_discovery_contract_revision=3" "$development_plan"
grep -Fq "season_discovery_extractor_version=season-discovery-v1" "$development_plan"

grep -Fq "project=outpick-664ae" "$production_plan"
grep -Fq "service=lookbook-import-worker" "$production_plan"
grep -Fq "storage_bucket=outpick-664ae.appspot.com" "$production_plan"
grep -Fq "worker_service_account=lookbook-import-worker@outpick-664ae.iam.gserviceaccount.com" "$production_plan"
grep -Fq "oidc_audience=https://lookbook-import-worker-715386497547.asia-northeast3.run.app" "$production_plan"
grep -Fq "task_service_account=lookbook-import-task-invoker@outpick-664ae.iam.gserviceaccount.com" "$production_plan"
grep -Fq "functions_service_account=715386497547-compute@developer.gserviceaccount.com" "$production_plan"
grep -Fq "season_discovery_contract_revision=3" "$production_plan"
grep -Fq "season_discovery_extractor_version=season-discovery-v1" "$production_plan"
grep -Fq -- "--no-traffic" "$production_plan"
grep -Fq -- "--no-allow-unauthenticated" "$production_plan"

production_service="$(plan_value "$production_plan" service)"
production_candidate_tag="$(plan_value "$production_plan" candidate_tag)"
[[ "$production_candidate_tag" =~ ^c[0-9]{10}$ ]]
if (( ${#production_service} + ${#production_candidate_tag} + 1 > 46 )); then
  echo "Production service와 candidate tag 결합 길이가 Cloud Run 제한을 초과합니다." >&2
  exit 1
fi

if OUTPICK_CONFIRM_WORKER_DEPLOY=wrong \
  "$DEPLOY_SCRIPT" production --deploy-candidate >"$TEMPORARY_DIRECTORY/rejected.txt" 2>&1; then
  echo "잘못된 Production 확인값이 배포 gate를 통과했습니다." >&2
  exit 1
fi

mock_bin="$TEMPORARY_DIRECTORY/mock-bin"
mock_log="$TEMPORARY_DIRECTORY/gcloud.log"
mkdir -p "$mock_bin"
cat >"$mock_bin/gcloud" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >>"$OUTPICK_GCLOUD_MOCK_LOG"
printf '\n' >>"$OUTPICK_GCLOUD_MOCK_LOG"

if [[ "$*" == *"run services describe"* && "$*" == *"json(status.traffic)"* ]]; then
  if [[ "${OUTPICK_GCLOUD_TRAFFIC_MODE:-single}" == "split" ]]; then
    printf '%s\n' '{"status":{"traffic":[{"revisionName":"lookbook-import-worker-a","percent":50},{"revisionName":"lookbook-import-worker-b","percent":50}]}}'
  else
    printf '%s\n' '{"status":{"traffic":[{"revisionName":"lookbook-import-worker-previous","percent":100},{"revisionName":"lookbook-import-worker-tagged","tag":"old-candidate"}]}}'
  fi
elif [[ "$*" == *"run services describe"* && "$*" == *"latestCreatedRevisionName"* ]]; then
  printf '%s\n' 'lookbook-import-worker-candidate'
elif [[ "$*" == *"run deploy"* ]]; then
  :
else
  echo "예상하지 못한 gcloud 호출입니다: $*" >&2
  exit 1
fi
EOF
chmod +x "$mock_bin/gcloud"

if ! PATH="$mock_bin:$PATH" \
  OUTPICK_GCLOUD_MOCK_LOG="$mock_log" \
  OUTPICK_CONFIRM_WORKER_DEPLOY=outpick-664ae/lookbook-import-worker \
    "$DEPLOY_SCRIPT" production --deploy-candidate >"$TEMPORARY_DIRECTORY/candidate.txt" 2>&1; then
  cat "$TEMPORARY_DIRECTORY/candidate.txt" >&2
  exit 1
fi

grep -Fq "previous_revision=lookbook-import-worker-previous" "$TEMPORARY_DIRECTORY/candidate.txt"
grep -Fq "candidate_revision=lookbook-import-worker-candidate" "$TEMPORARY_DIRECTORY/candidate.txt"
grep -Fq -- "--no-traffic" "$mock_log"
grep -Fq -- "--no-allow-unauthenticated" "$mock_log"

split_log="$TEMPORARY_DIRECTORY/gcloud-split.log"
if PATH="$mock_bin:$PATH" \
  OUTPICK_GCLOUD_MOCK_LOG="$split_log" \
  OUTPICK_GCLOUD_TRAFFIC_MODE=split \
  OUTPICK_CONFIRM_WORKER_DEPLOY=outpick-664ae/lookbook-import-worker \
    "$DEPLOY_SCRIPT" production --deploy-candidate >"$TEMPORARY_DIRECTORY/split.txt" 2>&1; then
  echo "분할 traffic 상태가 자동 rollback gate를 통과했습니다." >&2
  exit 1
fi
grep -Fq "단일 revision에 traffic 100%" "$TEMPORARY_DIRECTORY/split.txt"
if grep -Fq "run deploy" "$split_log"; then
  echo "분할 traffic 상태에서 candidate 배포가 호출됐습니다." >&2
  exit 1
fi

echo "Lookbook import worker deploy contract tests passed."
