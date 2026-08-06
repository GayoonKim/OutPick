# Lookbook Extraction Issue Operations Design

## 1. 목표

- 시즌 목록 discovery와 시즌 이미지 import에서 추출 로직이 불충분한 실패를 사용자 요청 없이 자동 기록한다.
- Codex는 사용자의 명시 요청이 있을 때만 IAM 비공개 운영 API/CLI로 issue cluster를 요약하고 선택한 문제의 정제된 evidence를 조회한다.
- 사용자가 선택한 cluster만 Codex와 보강하고, Production에 실제 반영된 revision을 서버가 검증한 뒤 영향 job의 재시도를 연다.
- 앱은 운영 도구를 노출하지 않고 `개선 대기 중 → 개선 처리 중 → 다시 가져오기 가능`만 표시한다.

## 2. 범위와 제외

포함:

- 두 extraction stage의 공통 분류, fingerprint, cluster와 redacted evidence.
- IAM 인증 목록/단일/batch 조회 API, 명시적 상태 mutation API와 Codex CLI.
- Production Worker runtime contract, release registry와 fix verifier.
- job별 retry readiness projection과 iOS 상태/action 단순화.
- 7일 occurrence evidence, 미해결 대표 evidence, terminal 60일 보존.

제외:

- 앱·웹 issue 목록, Jira, 담당자, 댓글, SLA, 칸반.
- 자동 코드 수정, 자동 fixture 승인, 자동 PR 생성·병합, 자동 Production 배포.
- Production 반영 직후 실패 job 자동 재실행.
- 배포된 적 없는 구형 앱을 위한 callable·field·UI 호환 계층.

## 3. 사용자·운영 흐름

1. Worker가 로직 불충분을 판정하면 occurrence evidence와 공통 fingerprint를 생성한다.
2. transaction이 같은 fingerprint cluster로 발생 횟수와 대표 evidence를 관리하고, job에 앱용 상태 projection을 기록한다.
3. 앱은 `open`을 `개선 대기 중`으로 표시하고 action을 제공하지 않는다.
4. 사용자가 Codex에 실패 요약을 요청하면 Codex CLI가 Development 또는 Production을 명시해 read API를 호출한다.
5. 사용자가 처리 cluster를 선택하면 Codex가 `startProcessing`을 compare-and-set으로 실행한다. 앱은 `개선 처리 중`으로 바뀐다.
6. ground truth가 부족하면 `needsGroundTruth`로 유지하고 Codex 대화에서 확인한 구조화된 판단만 API에 기록한다.
7. Codex가 코드·fixture를 보강하고 기존 Development QA와 PR 승인을 거쳐 Production에 배포한다.
8. release verifier가 Production 100% traffic, runtime contract, 대상 version, 실제 URL smoke 결과를 직접 확인한 뒤 cluster를 `fixed`로 바꾸고 정확히 영향받은 job만 retry-ready로 만든다.
9. 관리자가 앱에서 `다시 가져오기`를 실행한다. 시즌 목록은 새 job generation, 시즌 이미지는 새 review/dispatch generation을 사용한다.
10. 고정된 새 revision으로 실제 재시도 1건이 성공하면 cluster를 `verified`로 전환한다. 같은 fingerprint가 다시 발생하면 자동으로 `open`으로 되돌리고 `recurrenceCount`를 증가시킨다.

## 4. 실패 분류와 fingerprint

issue 대상은 `extractionLogicInsufficient`로 분류된 경우뿐이다. transient infrastructure, 잘못된 URL, 영구 접근 차단, 인증 필요, 취소, stale generation, 시즌 동일성 검토는 cluster를 만들지 않고 기존 action을 사용한다.

공통 fingerprint 입력:

```text
stage
+ platform
+ parserStrategy
+ sorted(failureReasons)
+ sorted(qualityReasons)
+ templateSignature
+ extractorMajorVersion
```

- SHA-256 결과의 앞 40자 lowercase hex를 document ID로 사용한다.
- source host는 ID와 cluster 집계에서 모두 제외한다.
- domain adapter 또는 host 특화 구조는 `platform/parserStrategy/templateSignature`가 달라 별도 cluster가 된다.
- 같은 `jobPath + generation + evidenceID` occurrence는 멱등 처리한다.
- 시즌 discovery도 이미지 import와 같은 redaction·template signature 계약을 생성한다.

## 5. 데이터 계약

### `lookbookExtractionEvidence/{evidenceID}`

개별 실행의 정제된 occurrence ledger다.

- `evidenceID`, `stage`, `brandID`, `jobPath`, `generation`.
- `issueFingerprint`, `storagePath`, `createdAt`, `expiresAt`.
- `expiresAt = createdAt + 7일`이며 기존 cleanup이 ledger와 결정적 Storage object를 삭제한다.
- Storage JSON에는 allowlist DOM 구조, redacted origin/path pattern, query key 이름, 후보/expected evidence와 extractor metadata만 둔다.

### `lookbookExtractionIssueClusters/{fingerprint}`

- identity: `fingerprint`, `stage`, `platform`, `parserStrategy`, `failureReasons`, `qualityReasons`, `templateSignature`, `extractorMajorVersion`.
- lifecycle: `status`, `stateVersion`, `firstSeenAt`, `lastSeenAt`, `updatedAt`.
- aggregation: `occurrenceCount`, `recurrenceCount`.
- adapter: `adapterScope`, `adapterKey`로 generic/platform/domain 보강 위치를 표시한다.
- representative: `representativeEvidenceID`, `representativeEvidenceStoragePath`, `representativeEvidenceStatus`, `representativeEvidenceScore`, `representativeBrandID`, `representativeJobPath`, `representativeEvidenceUpdatedAt`.
- processing: `processingStartedAt`, `processingStartedBy`, 선택적 `groundTruth`, `wontFixReason`.
- release: `blockedRuntimeVersion`, `fixedRuntimeVersion`, `fixedWorkerRevision`, `fixedAt`, `verifiedAt`, `verifiedByJobPath`, `verifiedByGeneration`.
- retention: active/fixed에는 `expiresAt`이 없고 `verified/wontFix`에는 terminal 시각 + 60일을 기록한다.

영향 brand/domain 표본과 부정확한 count는 cluster에 저장하지 않는다. 정확한 영향 job이 필요할 때 7일 occurrence ledger를 `issueFingerprint`와 runtime 경계로 조회한다.

### 대표 evidence

- occurrence object와 분리된 `lookbook-extraction-cluster-evidence/{fingerprint}/{evidenceID}.json` 중 cluster가 가리키는 한 개만 둔다.
- cluster 최초 생성 시 복사한다. 기존 자료가 없거나 missing이면 교체하고, ready이면 `schemaVersion → expected-count 존재 → candidate evidence 수 → structure token 수 → element 수` tuple이 더 큰 경우만 교체한다.
- 고유 object 경로에 새 대표를 쓴 뒤 이전 대표를 정리해 동시 교체가 최신 내용을 덮어쓰지 않게 한다.
- `open/inProgress/needsGroundTruth/fixed` 동안 expiry 없이 보존한다.
- `verified/wontFix` 전환 시 60일 expiry를 부여하고 cluster cleanup과 함께 삭제한다.
- 전체 HTML, script, screenshot, cookie, header, query value와 credential은 대표 evidence에도 금지한다.

### job projection

앱은 server-only cluster를 직접 읽지 않는다. 대상 discovery/import job에 다음 allowlist projection만 기록한다.

- `extractionIssueFingerprint`.
- `extractionIssueStatus`: `open | inProgress | needsGroundTruth | fixed | wontFix`.
- `blockedRuntimeVersion`.
- 선택적 `retryAvailableRuntimeVersion`, `retryAvailableAt`.
- 선택적 `resolvedByJobID` 또는 `resolvedByGeneration`.

`verified`는 성공한 새 job/generation이 화면의 기준이므로 기존 실패 job에 표시하지 않는다.

배포 전 구형 Worker 요청이 release projection 완료 뒤 늦게 도착할 수 있다. occurrence transaction은 cluster `blockedRuntimeVersion`을 같은 runtime 종류 안에서 단조 증가시키고, `fixed/verified` cluster보다 낮은 runtime의 늦은 job 또는 duplicate에는 job 상태 `fixed`와 cluster의 `fixedRuntimeVersion/fixedAt`을 retry-ready projection으로 기록한다. 이미 `verified`인 cluster에서 이 늦은 job의 실제 재시도가 성공하면 cluster terminal 상태와 최초 검증 이력은 유지하고 해당 job projection만 해결한다.

### runtime registry

서버 전용 `lookbookExtractionRuntime/current`:

- `workerService`, `workerRevision`, `workerTrafficPercent`, `workerSourceRevision`.
- `seasonDiscoveryContractRevision`, `seasonDiscoveryExtractorVersion`.
- `imageExtractorVersion`, bounded adapter version map.
- `verifiedAt`, `verifiedBy`, `verificationRunID`.

Worker의 IAM 비공개 `GET /runtime-contract`는 실행 중인 동일 필드를 반환한다. Functions의 compile-time 상수는 요청 schema 호환 범위에만 사용하고, extractor readiness의 source of truth로 사용하지 않는다.

### audit와 cleanup

- 모든 write/release operation은 `lookbookExtractionIssueAuditLogs/{eventID}`에 caller, action, fingerprint, before/after status와 stateVersion, 환경, request ID, 시각을 기록한다.
- 자유 형식 evidence·token·HTML은 audit에 기록하지 않는다.
- audit는 이벤트별 60일 TTL을 사용한다.
- terminal job 문서는 기존 합의대로 완료·실패 후 60일 보존한다. 이는 7일 occurrence evidence와 별도다.

## 6. 내부 API 계약

모든 endpoint는 v2 `onRequest`, `asia-northeast3`, IAM private invoker, POST JSON을 사용한다. URL query로 filter나 fingerprint를 받지 않는다.

### `lookbookExtractionIssueOpsRead`

공통 request: `{ apiVersion: 1, action, environment, requestID, payload }`.

- `listClusters`: 기본 status `open/inProgress/needsGroundTruth`, 기본 20개·최대 50개, `lastSeenAt DESC + fingerprint DESC` cursor. stage/status/seenAfter/recurrenceOnly filter만 허용한다. `brandID` filter는 제공하지 않는다.
- `getCluster`: fingerprint 하나의 allowlist cluster와 대표 evidence를 반환한다. 최근 occurrence brand/job 목록은 제공하지 않는다.
- `getClustersBatch`: fingerprint 최대 20개. 요청 순서를 보존하고 각 항목을 `found | missing | evidenceExpired`로 반환한다.

응답은 DTO allowlist로 새로 구성하며 Firestore document 전체를 직렬화하지 않는다. 임의 collection/path/field/order 입력은 거부한다.

### `lookbookExtractionIssueOpsWrite`

공통으로 `fingerprint`, `expectedStateVersion`, `requestID`를 요구한다.

- `startProcessing`: `open → inProgress`. 같은 request ID 재호출은 같은 결과를 반환한다.
- `markNeedsGroundTruth`: `inProgress → needsGroundTruth`.
- `recordGroundTruthAndResume`: `needsGroundTruth → inProgress`. 구조화된 expected count, 24자 hex candidate keys, `completeGallery | partialGallery | nonGallery | unknown` source classification과 최대 1,000자의 정제된 note만 허용한다.
- `reopen`: `needsGroundTruth/wontFix → open` 또는 운영자가 명시한 terminal 재검토. 사유 필수.
- `markWontFix`: `open/inProgress/needsGroundTruth → wontFix`. `sourceUnavailable | accessRestricted | ambiguousGroundTruth | unsupportedStructure | lowOperationalValue` reason과 최대 500자 note 필수.

클라이언트가 `fixed/verified`, runtime version, retry-ready를 직접 기록하는 action은 제공하지 않는다.

### `verifyLookbookExtractionFix`

입력은 fingerprint, expectedStateVersion, target stage/version, Worker revision과 source revision을 요구한다. verifier가 cluster의 대표 job을 서버 내부에서 읽고 같은 요청 안에서 전용 read-only smoke를 실행하므로 외부 diagnostic ID나 임의 URL을 받지 않는다.

서버가 다음을 모두 확인해야 성공한다.

1. 요청 환경이 Production이고 대상 Google project가 `outpick-664ae`다.
2. Cloud Run 서비스 traffic이 요청 revision에 100%다.
3. verifier identity로 `/runtime-contract`를 호출한 결과가 target과 정확히 일치한다.
4. `/smoke/extraction`은 대표 job의 실제 URL을 target revision으로 새로 추출하고 동일 logic issue가 사라졌음을 반환한다. completeness 계열은 ground truth count/key까지 일치해야 한다.
5. cluster는 `inProgress`, `needsGroundTruth`가 아니며 expected stateVersion과 blocked version 경계를 만족한다.
6. registry, cluster `fixed`, 영향 job retry projection과 audit을 bounded transaction/batch로 기록한다.

영향 job은 같은 `stage + fingerprint`이고 `blockedRuntimeVersion < fixedRuntimeVersion`인 미해결 job만 포함한다. 한 번에 처리할 상한을 두고 cursor가 남으면 reconciler가 이어서 처리한다. 자동 재실행은 하지 않는다.

## 7. 인증·보안

- 세 함수는 `allUsers`를 허용하지 않고 환경별 승인 운영자 principal에만 `roles/run.invoker`를 부여한다.
- Production은 service-account JSON을 저장하지 않는 환경별 전용 operator service account impersonation을 사용한다. 현재 개발자 계정에는 해당 계정의 ID Token Creator만, operator 계정에는 대상 함수의 Invoker만 부여한다.
- CLI는 `gcloud auth print-identity-token --impersonate-service-account=... --audiences=... --include-email`로 canonical audience가 있는 단기 token을 발급한다.
- 함수는 Cloud Run IAM 검증에 더해 Google ID token의 audience, issuer, expiry와 operator service-account email을 검증한다. 실제 impersonator 사용자 추적의 authoritative source는 Google Cloud Audit Logs이며 API audit에는 operator service account와 request ID를 기록한다.
- Development와 Production URL/audience/project는 CLI 내부 canonical table로 고정하며 사용자 입력 URL을 받지 않는다.
- `--environment`는 필수이고 Production write/release에는 `--confirm-production outpick-664ae`를 추가로 요구한다.
- token, Authorization header, evidence 원문은 stdout·Cloud Logging·audit에 출력하지 않는다.
- page/batch/scan/evidence/응답 크기와 `maxInstances`를 서버에서 제한한다. 전역 정밀 rate limit은 배포 인프라 게이트로 분리한다.
- Firestore rules는 cluster/evidence/runtime/audit에 대한 client read/write를 계속 거부한다.

## 8. CLI 계약

후보 위치는 `tools/lookbook-extraction-issue-ops/`다.

- `list --environment development|production [filters]`.
- `show --environment ... --fingerprint ...`.
- `show-batch --environment ... --fingerprint ...` 반복, 최대 20개.
- `start`, `needs-ground-truth`, `ground-truth`, `reopen`, `wont-fix`.
- `verify-fix`는 Production 명시 확인과 smoke run ID를 필수로 한다.
- `verify-fix`는 Production 명시 확인과 target runtime/Worker/source revision을 필수로 하며 smoke URL이나 run ID를 입력받지 않는다.

기본 출력은 사람이 읽는 요약이고 `--json`은 API allowlist DTO만 출력한다. CLI는 Firestore Admin SDK와 임의 URL 호출 기능을 포함하지 않는다.

현재 개발자 사용자 ID token 직접 호출은 Cloud Run에서 동작하지만 audience 없는 개발용 token이므로 Development read smoke에만 제한한다. Production read/write/release는 전용 operator service account impersonation만 사용한다.

## 9. iOS 계약

- 기존 `추출 개선 요청` 버튼과 Repository/UseCase/callable 연결을 제거한다.
- 이미지 correction 화면의 동일 extractor 즉시 `이미지 다시 찾기` action을 제거하고 `fixed` projection 뒤에만 재시도를 허용한다.
- 표시 매핑:
  - `open`: `개선 대기 중`, action 없음.
  - `inProgress/needsGroundTruth`: `개선 처리 중`, action 없음.
  - `fixed`: `다시 가져오기 가능`, 총 관리자 action 제공.
  - `wontFix`: 기존 URL 수정·취소·검토 등 원인별 안전 action만 제공.
- 시즌별 image import 행은 기존처럼 internal job ID가 아니라 시즌명을 표시한다.
- 전역 issue 목록·상세 화면과 ground-truth 입력 화면은 추가하지 않는다.

## 10. 동시성·오류 복구

- cluster `stateVersion` compare-and-set과 request ID ledger로 중복 호출을 멱등 처리한다.
- Worker occurrence와 운영 mutation이 경합하면 transaction 재시도 후 최신 terminal 상태를 존중한다. `fixed/verified` version 이상에서 같은 fingerprint가 발생한 경우에만 자동 reopen한다.
- verifier가 일부 job projection만 갱신하고 실패하지 않도록 release record와 cursor를 두고 reconciler가 멱등 재개한다.
- watchdog은 멈춘 extraction job을 기존 정책으로 종료/복구하며 issue를 임의로 `fixed`로 만들지 않는다.
- 대표 evidence 복사 실패는 occurrence 기록을 실패시키지 않고 cluster에 `representativeEvidenceStatus=missing`을 남겨 후속 occurrence에서 복구한다.

## 11. 완료 기준

- 두 stage의 로직 불충분만 자동으로 같은 계약의 cluster에 수렴한다.
- Codex가 Firestore 직접 접근 없이 목록과 최대 20개 상세를 안전하게 요약할 수 있다.
- 상태 mutation, release 검증과 retry projection이 stale·중복·부분 rollout을 차단한다.
- Production 검증 전에는 앱 재시도 action이 절대 열리지 않는다.
- 개별 occurrence는 7일, terminal job·cluster·대표 evidence는 확정된 60일 정책대로 정리된다.
- 레거시 개선 요청 UI/API/필드를 새 코드에서 읽거나 쓰지 않는다.

## 12. Phase 7 시즌 대표 이미지 보강 확장

- 시즌 후보 identity와 대표 이미지 표시를 분리하고 모든 브랜드에 목록 이미지 우선, 시즌 상세 콘텐츠 영역의 최상단 첫 유효 이미지 fallback을 적용하는 확장 설계를 확정했다.
- Cafe24 등 Platform/Domain 규칙은 Generic 콘텐츠 영역 식별을 보강할 뿐 적용 조건이 아니다. 페이지 전체 첫 이미지와 low-confidence 전체 페이지 후보는 사용하지 않는다.
- 상세 보강은 후보 성공 판정과 분리된 bounded best-effort 작업이며, 후보 최대 30개·동시 3개·전체 15초 경계를 사용한다.
- candidate provenance, job 집계, runtime `contract:3`, 테스트와 Development QA의 상세 계약은 `phase-7-season-cover-enrichment.md`를 source of truth로 사용한다.
- 로컬 구현과 자동 검증을 완료했다. Development/Production 배포와 실제 URL QA는 별도 승인 전 수행하지 않았다.
