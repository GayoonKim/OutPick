#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKER_DIR="$ROOT_DIR/tools/lookbook-import-worker"
REGION="asia-northeast3"
season_discovery_contract_revision="3"
season_discovery_extractor_version="season-discovery-v1"

usage() {
  cat <<'EOF'
Usage:
  scripts/ai/deploy-lookbook-import-worker.sh development [--plan]
  scripts/ai/deploy-lookbook-import-worker.sh production [--plan]
  scripts/ai/deploy-lookbook-import-worker.sh development --deploy-candidate
  scripts/ai/deploy-lookbook-import-worker.sh production --deploy-candidate
  scripts/ai/deploy-lookbook-import-worker.sh development --deploy-candidate \
    --gate-summary output/verification/<worker-gate-run>/summary.json

The default action is --plan. A candidate deploy always uses --no-traffic.
Development may deploy a verified Worker snapshot from a passed Worker gate.
Production continues to require a clean committed tree.
Production candidate deploy additionally requires:
  OUTPICK_CONFIRM_WORKER_DEPLOY=outpick-664ae/lookbook-import-worker
EOF
}

environment_name="${1:-}"
action="${2:---plan}"
gate_summary_argument=""

if [[ "$#" -eq 4 && "${3:-}" == "--gate-summary" && -n "${4:-}" ]]; then
  gate_summary_argument="$4"
elif [[ "$#" -gt 2 ]]; then
  usage >&2
  exit 2
fi

case "$environment_name" in
  development)
    project_id="outpick-test"
    service_name="lookbook-import-worker-development"
    worker_service_account="outpick-lookbook-worker-dev@outpick-test.iam.gserviceaccount.com"
    storage_bucket="outpick-test.firebasestorage.app"
    oidc_audience="https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app"
    task_service_account="outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com"
    functions_service_account="86635107099-compute@developer.gserviceaccount.com"
    ;;
  production)
    project_id="outpick-664ae"
    service_name="lookbook-import-worker"
    worker_service_account="lookbook-import-worker@outpick-664ae.iam.gserviceaccount.com"
    storage_bucket="outpick-664ae.appspot.com"
    oidc_audience="https://lookbook-import-worker-715386497547.asia-northeast3.run.app"
    task_service_account="lookbook-import-task-invoker@outpick-664ae.iam.gserviceaccount.com"
    functions_service_account="715386497547-compute@developer.gserviceaccount.com"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

case "$action" in
  --plan|--deploy-candidate)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ -n "$gate_summary_argument" &&
      ( "$environment_name" != "development" || "$action" != "--deploy-candidate" ) ]]; then
  echo "검증된 dirty source snapshot은 Development candidate 배포에만 허용합니다." >&2
  exit 2
fi

# Cloud Run은 service명과 traffic tag의 결합 길이를 46자로 제한한다.
# Development service명이 길어 분 단위 UTC timestamp를 포함한 11자 tag를 사용한다.
candidate_tag="c$(date -u +%y%m%d%H%M)"
if [[ -n "$gate_summary_argument" ]]; then
  # Q7 runner와 Functions는 안정된 0% candidate tag URL을 사용한다.
  candidate_tag="q7-20261006"
fi
source_revision="$(git -C "$ROOT_DIR" rev-parse HEAD)"
deployment_source_dir="$WORKER_DIR"
verification_digest=""
snapshot_manifest=""
if [[ -n "$gate_summary_argument" ]]; then
  snapshot_root="$ROOT_DIR/output/lookbook-import-performance/worker-deploy-snapshots"
  mkdir -p "$snapshot_root"
  snapshot_directory="$snapshot_root/candidate-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  if [[ "$gate_summary_argument" = /* ]]; then
    gate_summary_path="$gate_summary_argument"
  else
    gate_summary_path="$ROOT_DIR/$gate_summary_argument"
  fi
  snapshot_info="$(node "$ROOT_DIR/scripts/ai/create-lookbook-import-worker-deploy-snapshot.mjs" \
    --project "$ROOT_DIR" \
    --gate-summary "$gate_summary_path" \
    --snapshot "$snapshot_directory")"
  deployment_source_dir="$(printf '%s\n' "$snapshot_info" | sed -n 's/^snapshot=//p')"
  snapshot_manifest="$(printf '%s\n' "$snapshot_info" | sed -n 's/^manifest=//p')"
  verification_digest="$(printf '%s\n' "$snapshot_info" | sed -n 's/^verification_digest=//p')"
  source_revision="$(printf '%s\n' "$snapshot_info" | sed -n 's/^source_revision=//p')"
  [[ -d "$deployment_source_dir" && -f "$snapshot_manifest" &&
     "$verification_digest" =~ ^[a-f0-9]{64}$ &&
     "$source_revision" =~ ^[a-f0-9]{40}$ ]] || {
    echo "검증된 Worker source snapshot을 만들지 못했습니다." >&2
    exit 1
  }
fi
env_vars="OUTPICK_FIREBASE_PROJECT_ID=$project_id"
env_vars+=",OUTPICK_FIREBASE_STORAGE_BUCKET=$storage_bucket"
env_vars+=",OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY=3"
env_vars+=",OUTPICK_IMPORT_OIDC_AUDIENCE=$oidc_audience"
env_vars+=",OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL=$task_service_account"
env_vars+=",OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL=$functions_service_account"
env_vars+=",OUTPICK_WORKER_SOURCE_REVISION=$source_revision"
if [[ -n "$verification_digest" ]]; then
  env_vars+=",OUTPICK_WORKER_VERIFICATION_DIGEST=$verification_digest"
fi
if [[ "$environment_name" == "development" ]]; then
  env_vars+=",OUTPICK_IMPORT_PERFORMANCE_ENABLED=true"
  env_vars+=",OUTPICK_IMPORT_RECOVERY_SERVICE_ACCOUNT_EMAIL=lookbook-import-recovery@outpick-test.iam.gserviceaccount.com"
fi
if [[ -n "${OUTPICK_Q7_RETRY_FAULT_CAMPAIGN:-}" ]]; then
  if [[ "$environment_name" != "development" || -z "$gate_summary_argument" ||
        ! "$OUTPICK_Q7_RETRY_FAULT_CAMPAIGN" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$ ]]; then
    echo "고의 장애는 검증된 Development candidate campaign에만 허용합니다." >&2
    exit 2
  fi
  env_vars+=",OUTPICK_Q7_RETRY_FAULT_CAMPAIGN=$OUTPICK_Q7_RETRY_FAULT_CAMPAIGN"
fi
env_vars+=",OUTPICK_SEASON_DISCOVERY_CONTRACT_REVISION=$season_discovery_contract_revision"
env_vars+=",OUTPICK_SEASON_DISCOVERY_EXTRACTOR_VERSION=$season_discovery_extractor_version"

deploy_command=(
  gcloud run deploy "$service_name"
  --project "$project_id"
  --region "$REGION"
  --source "$deployment_source_dir"
  --service-account "$worker_service_account"
  --set-env-vars "$env_vars"
  --no-allow-unauthenticated
  --no-traffic
  --tag "$candidate_tag"
  --quiet
)

print_contract() {
  printf 'environment=%s\n' "$environment_name"
  printf 'project=%s\n' "$project_id"
  printf 'service=%s\n' "$service_name"
  printf 'region=%s\n' "$REGION"
  printf 'worker_service_account=%s\n' "$worker_service_account"
  printf 'storage_bucket=%s\n' "$storage_bucket"
  printf 'oidc_audience=%s\n' "$oidc_audience"
  printf 'task_service_account=%s\n' "$task_service_account"
  printf 'functions_service_account=%s\n' "$functions_service_account"
  printf 'candidate_tag=%s\n' "$candidate_tag"
  printf 'source_revision=%s\n' "$source_revision"
  printf 'verification_digest=%s\n' "${verification_digest:-not-provided}"
  printf 'deployment_source=%s\n' "$deployment_source_dir"
  printf 'snapshot_manifest=%s\n' "${snapshot_manifest:-not-created}"
  printf 'season_discovery_contract_revision=%s\n' "$season_discovery_contract_revision"
  printf 'season_discovery_extractor_version=%s\n' "$season_discovery_extractor_version"
  printf 'command='
  printf '%q ' "${deploy_command[@]}"
  printf '\n'
}

print_contract

if [[ "$action" == "--plan" ]]; then
  exit 0
fi

if [[ -z "$verification_digest" ]] &&
   { ! git -C "$ROOT_DIR" diff --quiet ||
     ! git -C "$ROOT_DIR" diff --cached --quiet; }; then
  echo "candidate 배포는 commit된 clean worktree에서만 허용합니다." >&2
  exit 1
fi

expected_confirmation="$project_id/$service_name"
if [[ "$environment_name" == "production" &&
      "${OUTPICK_CONFIRM_WORKER_DEPLOY:-}" != "$expected_confirmation" ]]; then
  echo "Production candidate 배포에는 다음 확인값이 필요합니다:" >&2
  echo "OUTPICK_CONFIRM_WORKER_DEPLOY=$expected_confirmation" >&2
  exit 2
fi

traffic_state="$(
  gcloud run services describe "$service_name" \
    --project "$project_id" \
    --region "$REGION" \
    --format='json(status.traffic)'
)"
previous_revision="$(
  printf '%s' "$traffic_state" | node -e '
    let input = "";
    process.stdin.on("data", (chunk) => { input += chunk; });
    process.stdin.on("end", () => {
      const serving = (JSON.parse(input).status?.traffic ?? [])
        .filter((entry) => Number(entry.percent ?? 0) > 0);
      if (serving.length !== 1 || Number(serving[0].percent) !== 100 || !serving[0].revisionName) {
        process.exit(1);
      }
      process.stdout.write(serving[0].revisionName);
    });
  '
)" || {
  echo "단일 revision에 traffic 100%가 할당된 상태만 자동 rollback 기준으로 지원합니다." >&2
  exit 1
}

if [[ -z "$verification_digest" ]]; then
  (
    cd "$WORKER_DIR"
    npm test
    npm run lint
    npm run test:fixtures
  )
fi

printf 'previous_revision=%s\n' "$previous_revision"
"${deploy_command[@]}"

candidate_revision="$(
  gcloud run services describe "$service_name" \
    --project "$project_id" \
    --region "$REGION" \
    --format='value(status.latestCreatedRevisionName)'
)"
[[ -n "$candidate_revision" ]] || {
  echo "candidate revision을 확인할 수 없습니다." >&2
  exit 1
}

printf 'candidate_revision=%s\n' "$candidate_revision"
printf 'traffic은 변경하지 않았습니다. 검증·전환·rollback은 다음 runbook을 따르세요.\n'
printf 'docs/ai/runbooks/LOOKBOOK_IMPORT_WORKER_DEPLOYMENT.md\n'
