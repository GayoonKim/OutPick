# Lookbook Import Worker 배포 Runbook

## 목적

Development와 Production Worker의 project, Storage bucket, URL/OIDC audience, 호출 계정이 교차되지 않도록 배포 계약과 candidate 검증·traffic 전환·rollback 절차를 고정한다.

실제 배포는 사용자 명시 승인 후에만 진행한다. 스크립트 기본 동작은 명령과 계약만 출력하는 `--plan`이며 외부 상태를 변경하지 않는다.

## 진입점

Q7 K/L 전용 장애 검증(2026-10-07): 사용자 승인 뒤 `OUTPICK_Q7_RETRY_FAULT_CAMPAIGN=<고정 UUIDv4>`와 passed Worker `--gate-summary`를 함께 사용한다. 이 설정은 Development verified snapshot에서만 허용하며 Production·공개 endpoint로 활성화하지 않는다. 시작 시 service/project/revision/digest를 검증하고 실제 소비는 서버 원장의 exact campaign/batch/job/execution·20분 창을 요구한다. 새 승인 batch/수동 execution에 장치를 반복 적용하지 않는다. [실행안·한도](../tasks/lookbook-import-performance/q7-retry-development-execution-plan.md), [진입점](../entrypoints/FIREBASE.md).

- 배포 계약: `scripts/ai/deploy-lookbook-import-worker.sh`
- dirty 작업트리의 Development 배포 snapshot: `scripts/ai/create-lookbook-import-worker-deploy-snapshot.mjs`
- 계약 테스트: `scripts/ai/test-deploy-lookbook-import-worker.sh`
- Worker 시작 검증: `tools/lookbook-import-worker/src/config.ts`
- HTTP/OIDC 경계: `tools/lookbook-import-worker/src/server.ts`, `oidc-auth.ts`

## 1. 배포 계획 확인

```bash
scripts/ai/deploy-lookbook-import-worker.sh development --plan
scripts/ai/deploy-lookbook-import-worker.sh production --plan
scripts/ai/test-deploy-lookbook-import-worker.sh
```

계획 출력에서 project, service, runtime service account, Storage bucket, OIDC audience, Cloud Tasks 계정, Functions 계정을 확인한다. URL이나 계정을 명령행에서 별도로 덮어쓰지 않는다.

## 2. 사전 상태 기록

대상 환경의 현재 Ready revision과 traffic을 기록한다.

```bash
gcloud run services describe {service} \
  --project {project} \
  --region asia-northeast3 \
  --format='yaml(status.latestReadyRevisionName,status.traffic,spec.template.spec.serviceAccountName,spec.template.spec.containers[0].env)'
```

Production 기준:

- project: `outpick-664ae`
- service: `lookbook-import-worker`
- rollback 기준: 배포 직전 traffic 100%가 할당된 단일 revision

배포 스크립트는 태그가 가리키는 0% revision을 rollback 대상으로 선택하지 않는다. 분할 traffic처럼 0% 초과 revision이 둘 이상이면 자동 rollback 기준을 임의로 단순화하지 않고 candidate 배포 전에 중단한다.

## 3. Candidate 배포

Candidate 배포는 `--no-traffic`으로 새 revision만 만들며 기존 사용자 traffic을 바꾸지 않는다.
Candidate tag는 Cloud Run의 service명과 tag 결합 길이 46자 제한을 지키는 `cYYMMDDHHMM` 형식을 사용한다. Development의 긴 service명도 이 계약으로 revision 생성 전에 차단되지 않는다.

Development:

```bash
scripts/ai/deploy-lookbook-import-worker.sh development --deploy-candidate
```

작업트리에 다른 미커밋 변경이 있어도 Development candidate를 검증된 Worker gate 결과로 배포해야 할 때는 다음 형식을 사용한다.

```bash
scripts/ai/deploy-lookbook-import-worker.sh development --deploy-candidate \
  --gate-summary output/verification/{worker-gate-run}/summary.json
```

이 경로는 Production에서 거부된다. 스크립트는 Worker 필수 gate가 모두 통과했고 현재 입력 digest·HEAD가 summary와 일치하는지 확인한 뒤 Worker 파일만 `output/lookbook-import-performance/worker-deploy-snapshots/`에 복사한다. snapshot manifest와 SHA-256을 남기고, candidate revision 환경변수 `OUTPICK_WORKER_VERIFICATION_DIGEST`에 gate source digest를 기록한다. Development에서는 Q7 관측용 `OUTPICK_IMPORT_PERFORMANCE_ENABLED=true`도 설정한다. 새 candidate는 `--no-traffic`으로 생성하며 기존 100% traffic은 유지한다. Q7 runner가 사용하는 안정된 tag `q7-20261006`만 새 candidate revision으로 옮기므로, 고정 tag URL을 설정한 Functions는 새 Worker를 호출하고 다른 traffic은 바뀌지 않는다. 이 경로에서는 gate summary가 정확한 현재 소스를 증명하므로 배포 전 Worker 테스트를 재실행하지 않는다. summary 누락·실패·오래된 digest·소스 변경은 배포 전에 거부한다.

배포 출력에서 `snapshot_manifest`의 verification digest와 candidate revision을 기록한다. Q7 runner 실행 전 같은 digest를 `OUTPICK_Q7_EXPECTED_WORKER_VERIFICATION_DIGEST`에 설정한다. Q7 preflight는 해당 값이 고정 tag가 가리키는 candidate revision의 digest 환경변수와 일치하지 않으면 모든 제품 mutation 전에 중단한다. candidate Ready 상태, tag 대상 revision, 0% tag/기존 100% traffic, `requestSeasonImport` URL, 두 Cloud Tasks queue의 대기 작업 0건도 읽기 전용으로 확인한다.

Production:

```bash
OUTPICK_CONFIRM_WORKER_DEPLOY=outpick-664ae/lookbook-import-worker \
scripts/ai/deploy-lookbook-import-worker.sh production --deploy-candidate
```

스크립트 출력의 `previous_revision`, `candidate_revision`, `candidate_tag`를 QA 기록에 남긴다.

## 4. Candidate 검증

1. `candidate_revision`이 Ready인지 확인한다. snapshot 배포라면 revision의 `OUTPICK_WORKER_VERIFICATION_DIGEST`가 출력된 manifest의 verification digest와 일치하는지도 확인한다.
2. Candidate tag URL에 각 환경의 정확한 audience로 발급한 OIDC token을 사용한다.
3. `/readyz`가 200인지 확인한다.
4. Cloud Tasks 계정의 빈 `/tasks/import-job` 요청이 IAM과 앱 인증을 통과해 payload 검증 500에 도달하는지 확인한다.
5. Functions 계정의 빈 `/tasks/discover-seasons-diagnostic` 요청이 payload 검증 500에 도달하는지 확인한다.
6. Functions 계정으로 `/tasks/import-job`을 호출하면 403인지 확인한다.
7. Candidate revision의 ERROR 로그가 0건인지 확인한다.

서비스 계정 ID token은 해당 환경의 canonical audience로 발급해야 한다. OIDC 검증만 필요한 운영자에게 광범위한 `roles/iam.serviceAccountTokenCreator`를 부여하지 않는다. 승인된 1인 운영자는 Development와 Production의 Functions/Task 서비스 계정 각각의 exact 리소스에만 `roles/iam.serviceAccountOpenIdTokenCreator`를 유지하고, 사용자 access token으로 IAM Credentials `generateIdToken`을 직접 호출한다. 이 좁은 역할은 `gcloud --impersonate-service-account`용 access token 권한을 포함하지 않으므로 아래 REST 호출을 사용한다. 임의 계정, 사용자 ID token, 서비스 계정 key로 대체하지 않는다. 운영자 계정 변경, 운영 인력 추가, CI 전환 또는 계정 보안 사고 시 binding을 재검토한다.

```bash
operator_access_token="$(gcloud auth print-access-token --account=gayunkim.1@gmail.com)"
curl -sS --fail -X POST \
  -H "Authorization: Bearer $operator_access_token" \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d '{"audience":"{canonical_worker_audience}","includeEmail":true}' \
  'https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/{service_account_email}:generateIdToken'
```

응답의 `token`만 현재 shell 변수로 받아 candidate 호출에 사용하고 파일·로그·하네스에는 기록하지 않는다.

```bash
gcloud run revisions describe {candidate_revision} \
  --project {project} \
  --region asia-northeast3 \
  --format='yaml(status.conditions,metadata.labels,spec.serviceAccountName)'

gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.revision_name="{candidate_revision}" AND severity>=ERROR' \
  --project {project} \
  --limit 20
```

## 5. Traffic 전환

### Development Q7 복구 호출

사용자 승인(2026-10-06): 운영자 `gayunkim.1@gmail.com` 하나에 recovery SA 리소스의 `roles/iam.serviceAccountOpenIdTokenCreator`, recovery SA에는 특정 Development Worker service의 `roles/run.invoker`만 추가한다. runtime SA에는 `logging.logEntries.list`만 있는 custom role을 추가한다. 이 권한은 프로젝트 일반 로그 읽기이며 code query는 exact service/revision/trace만 사용한다. SA key·넓은 TokenCreator·로그 수정/삭제·Production 변경은 포함하지 않는다.

배포 스크립트가 Development recovery env를 설정하고 Q7 preflight가 exact email을 확인한다. `scripts/lookbook-import-recovery.mjs`는 `src/queue/recovery-auth.ts`를 통해 사용자 access token으로 `generateIdToken`을 직접 호출한다. inspect 대상 revision은 현재 candidate가 아니라 기존 run의 revision이다. inspect 통과 후 report digest/state revision/고정 decision ID로 `settle-correction`을 호출한다. `/recovery/resume`으로 terminal correction 결과를 재실행하지 않는다.

Candidate 검증을 모두 통과하고 사용자가 Production 전환을 명시 승인한 뒤에만 실행한다.

```bash
gcloud run services update-traffic {service} \
  --project {project} \
  --region asia-northeast3 \
  --to-revisions {candidate_revision}=100
```

전환 후 Ready/traffic 100%, queue pending, 최근 ERROR, 실제 import smoke를 다시 확인한다.

## 6. Rollback

Candidate 검증 실패 시 traffic을 전환하지 않고 candidate를 보류한다. 전환 후 오류가 발생하면 사전에 기록한 revision으로 traffic을 되돌린다.

```bash
gcloud run services update-traffic {service} \
  --project {project} \
  --region asia-northeast3 \
  --to-revisions {previous_revision}=100
```

rollback 후 Ready/traffic 100%, 최근 ERROR, queue 상태를 다시 확인하고 실패 revision과 원인을 QA 기록에 남긴다.
