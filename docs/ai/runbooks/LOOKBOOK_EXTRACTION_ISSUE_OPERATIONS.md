# Lookbook Extraction Issue Operations Runbook

## 목적과 경계

- `lookbookExtractionIssueOpsRead`는 bounded 목록·단일·최대 20개 batch 상세를 제공한다.
- `lookbookExtractionIssueOpsWrite`는 CAS 기반 운영 상태 변경만 제공한다.
- 두 Function은 `private` invoker이며 Firestore 직접 운영, 임의 endpoint, `fixed/verified/retry-ready` client write를 허용하지 않는다.
- 목록·상세 응답에는 최근 브랜드/job 사례를 넣지 않는다. Phase 4에서 필요한 정확한 영향 job은 `extractionIssueFingerprint` projection으로 조회한다.

## 환경별 principal

| 환경 | Project | Operator service account |
| --- | --- | --- |
| Development | `outpick-test` | `outpick-extraction-ops-dev@outpick-test.iam.gserviceaccount.com` |
| Production | `outpick-664ae` | `outpick-extraction-ops-prod@outpick-664ae.iam.gserviceaccount.com` |

Development principal과 IAM은 생성·적용했다. Production principal/IAM은 별도 명시 승인 전까지 생성하거나 변경하지 않는다.

개발자에게는 operator service account의 `roles/iam.serviceAccountTokenCreator`, operator에게는 read/write Cloud Run service의 `roles/run.invoker`가 필요하다. Functions 내부에서도 project, environment, audience, verified email을 다시 검증한다.

## Audience 설정

각 endpoint의 audience는 Firebase 표시 URL이 아니라 실제 Cloud Run `serviceConfig.uri`다.

```bash
gcloud functions describe lookbookExtractionIssueOpsRead \
  --gen2 --region asia-northeast3 --project outpick-test \
  --format='value(serviceConfig.uri)'
```

결과를 Functions 환경 변수에 각각 설정한다.

- `OUTPICK_EXTRACTION_OPS_READ_AUDIENCE`
- `OUTPICK_EXTRACTION_OPS_WRITE_AUDIENCE`
- `OUTPICK_EXTRACTION_OPS_RELEASE_AUDIENCE`

CLI는 호출 때마다 고정 function의 실제 URI를 조회하고 그 URI를 audience로 한 단기 identity token을 impersonation으로 발급한다. token과 Authorization header는 출력하지 않는다.

## CLI

```bash
cd tools/lookbook-extraction-issue-ops
npm run lint
npm test
npm run build
node src/index.js list --environment development --limit 20
```

지원 command:

- read: `list`, `show`, `show-batch`
- mutation: `start`, `needs-ground-truth`, `ground-truth`, `reopen`, `wont-fix`
- release: `verify-fix`—선택한 환경의 traffic/runtime/source revision과 실제 대표 job smoke를 한 번에 검증한다. Production만 추가 확인값을 요구한다.

`ground-truth`의 `sourceClassification`은 `completeGallery | partialGallery | nonGallery | unknown`, `wont-fix` 사유는 `sourceUnavailable | accessRestricted | ambiguousGroundTruth | unsupportedStructure | lowOperationalValue`만 허용한다.

## Development 배포 상태와 검증

- Firestore의 season discovery/import job `extractionIssueFingerprint` collection-group index와 audit/fix verification/fix release `expiresAt` TTL을 `outpick-test`에 적용했다.
- read/write/release/reconcile Functions를 `outpick-test`에 배포하고 Development operator와 verifier execution identity에 최소 Cloud Run 권한을 부여했다.
- Worker `lookbook-import-worker-development-00006-pob`는 traffic 100%이며 rollback은 `00004-xal`이다. candidate identity smoke와 전환 후 ERROR/queue 0건을 확인했다.
- 실제 extraction fix가 없는 운영 시스템 QA에서 합성 `fixed`를 만들지 않는다. 첫 실제 runtime 상승 때 두 stage의 verifier→retry→verified를 이 runbook의 필수 게이트로 수행한다.

## Production 게이트

다음 항목은 각각 별도 사용자 승인이 필요하다.

1. Production operator service account 생성과 개발자 impersonation 권한 부여.
2. Production read/write/release Functions 환경 변수·배포와 Cloud Run invoker 부여.
3. release Function 실행 service account에 Production Worker `roles/run.invoker`와 Cloud Run 조회용 `roles/run.viewer` 부여.
4. Worker candidate에 `OUTPICK_WORKER_SOURCE_REVISION`, discovery contract/extractor env를 고정하고 `/runtime-contract`, `/smoke/extraction`을 no-traffic 상태에서 검증.
5. Production Firestore verification run/release TTL 적용.
6. 실제 Production mutation, Worker traffic 전환, fix smoke, legacy callable/data 정리.

Production write CLI는 `--confirm-production outpick-664ae`도 요구한다. 이 문자열은 실수 방지 장치일 뿐 위 승인을 대체하지 않는다.
