# Lookbook Import Worker 배포 Runbook

## 목적

Development와 Production Worker의 project, Storage bucket, URL/OIDC audience, 호출 계정이 교차되지 않도록 배포 계약과 candidate 검증·traffic 전환·rollback 절차를 고정한다.

실제 배포는 사용자 명시 승인 후에만 진행한다. 스크립트 기본 동작은 명령과 계약만 출력하는 `--plan`이며 외부 상태를 변경하지 않는다.

## 진입점

- 배포 계약: `scripts/ai/deploy-lookbook-import-worker.sh`
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

Production:

```bash
OUTPICK_CONFIRM_WORKER_DEPLOY=outpick-664ae/lookbook-import-worker \
scripts/ai/deploy-lookbook-import-worker.sh production --deploy-candidate
```

스크립트 출력의 `previous_revision`, `candidate_revision`, `candidate_tag`를 QA 기록에 남긴다.

## 4. Candidate 검증

1. `candidate_revision`이 Ready인지 확인한다.
2. Candidate tag URL에 각 환경의 정확한 audience로 발급한 OIDC token을 사용한다.
3. `/readyz`가 200인지 확인한다.
4. Cloud Tasks 계정의 빈 `/tasks/import-job` 요청이 IAM과 앱 인증을 통과해 payload 검증 500에 도달하는지 확인한다.
5. Functions 계정의 빈 `/tasks/discover-seasons-diagnostic` 요청이 payload 검증 500에 도달하는지 확인한다.
6. Functions 계정으로 `/tasks/import-job`을 호출하면 403인지 확인한다.
7. Candidate revision의 ERROR 로그가 0건인지 확인한다.

서비스 계정 ID token은 해당 환경의 canonical audience로 발급해야 한다. 운영자가 서비스 계정을 impersonate할 권한이 없으면 임의 계정이나 사용자 token으로 대체하지 않고 권한 있는 Cloud Shell 또는 승인된 QA 절차를 사용한다.

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
