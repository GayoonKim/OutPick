#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKER_DIR="$ROOT_DIR/tools/lookbook-import-worker"
REGION="asia-northeast3"

usage() {
  cat <<'EOF'
Usage:
  scripts/ai/deploy-lookbook-import-worker.sh development [--plan]
  scripts/ai/deploy-lookbook-import-worker.sh production [--plan]
  scripts/ai/deploy-lookbook-import-worker.sh development --deploy-candidate
  scripts/ai/deploy-lookbook-import-worker.sh production --deploy-candidate

The default action is --plan. A candidate deploy always uses --no-traffic.
Production candidate deploy additionally requires:
  OUTPICK_CONFIRM_WORKER_DEPLOY=outpick-664ae/lookbook-import-worker
EOF
}

environment_name="${1:-}"
action="${2:---plan}"

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

# Cloud Run은 service명과 traffic tag의 결합 길이를 46자로 제한한다.
# Development service명이 길어 분 단위 UTC timestamp를 포함한 11자 tag를 사용한다.
candidate_tag="c$(date -u +%y%m%d%H%M)"
env_vars="OUTPICK_FIREBASE_PROJECT_ID=$project_id"
env_vars+=",OUTPICK_FIREBASE_STORAGE_BUCKET=$storage_bucket"
env_vars+=",OUTPICK_IMPORT_ASSET_SYNC_CONCURRENCY=3"
env_vars+=",OUTPICK_IMPORT_OIDC_AUDIENCE=$oidc_audience"
env_vars+=",OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL=$task_service_account"
env_vars+=",OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL=$functions_service_account"

deploy_command=(
  gcloud run deploy "$service_name"
  --project "$project_id"
  --region "$REGION"
  --source "$WORKER_DIR"
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
  printf 'command='
  printf '%q ' "${deploy_command[@]}"
  printf '\n'
}

print_contract

if [[ "$action" == "--plan" ]]; then
  exit 0
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

(
  cd "$WORKER_DIR"
  npm test
  npm run lint
  npm run test:fixtures
)

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
