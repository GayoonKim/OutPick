# Firebase Entrypoints

## 목적과 source of truth

Firebase 변경 시 Functions, Firestore, Storage의 실제 경계를 찾기 위한 인덱스다.

| 영역 | source of truth | workflow |
| --- | --- | --- |
| Functions | `functions/src/index.ts`, `functions/src/{core,shared,auth,brand,chat,lookbook}/` | `.codex/skills/firebase-functions-workflow/SKILL.md` |
| Firestore rules | `firestore.rules` | `.codex/skills/firestore-workflow/SKILL.md` |
| Firestore indexes | `firestore.indexes.json` | `.codex/skills/firestore-workflow/SKILL.md` |
| Storage rules | `storage.rules`, root `firebase.json` | 배포 전 rules dry-run과 운영 권한 확인 |
| iOS callable transport | `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift` | 기능별 Repository/Client와 mapper를 함께 확인 |

- 운영 배포 revision과 일회성 QA 로그는 관련 task의 `progress.md`에 기록한다.
- 장기 기술 결정은 `docs/ai/ADR.md`, 데이터 계약은 `docs/ai/DATA_SCHEMA.md`를 확인한다.
- 데이터 삭제, rules 완화, 운영 배포 범위가 모호하면 구현/배포를 멈추고 사용자와 논의한다.

## Functions 코드 지도

`functions/src/index.ts`는 현재 53개 배포 이름의 명시적 flat re-export만 가진다. 실제 handler와 helper는 아래 기능 module에서 찾는다.

Phase 4 구현 결과와 결정은 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-4-firebase-functions.md`, contract/service/policy 테스트는 `phase-4-firebase-functions-tests.md`와 `functions/src/**/*.test.ts`를 따른다.

Phase 6 전체 회귀와 운영 배포는 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-integration-tests.md`, `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-deployment.md`를 따른다. Functions는 Socket gate 통과 후 49개 export 전체를 배포하며 prior source rollback 기준을 확보하지 못하면 배포하지 않는다.

| 변경 목적 | 검색할 함수/파일 |
| --- | --- |
| 인증 | `functions/src/auth/functions.ts`, `kakaoService.ts` |
| 총 관리자·브랜드 권한 | `functions/src/shared/brandAuthorization.ts` |
| 브랜드 요청 | `functions/src/brand/requests/functions.ts` |
| 브랜드 관리 | `functions/src/brand/admin/functions.ts`, `shared/brandValidation.ts` |
| 룩북 삭제 lifecycle | `functions/src/lookbook/deletion/`과 아래 전용 섹션 |
| engagement/comment/safety | `functions/src/lookbook/{engagement,comments,safety}/functions.ts` |
| 시즌 import·추출 진단 | `functions/src/lookbook/import/` |
| extraction review·재분석·trust | `functions/src/lookbook/import/functions.ts`, `reviewContract.ts` |
| extraction evidence cleanup | `functions/src/lookbook/import/functions.ts`, `evidenceCleanup.ts` |
| existing-season repair preview/apply | `functions/src/lookbook/import/functions.ts`, `repairContract.ts` |
| Chat room cleanup | `functions/src/chat/cleanup/functions.ts`, `cleanupService.ts` |

기본 검증:

```bash
cd functions
npm test
npm run lint
npm run build
```

운영 배포는 사용자 승인 후 workflow가 지정한 명령을 사용한다.

## 브랜드 권한과 요청

### 권한

- 총 관리자 source: `brandAdmins/{uid}.isActive == true`.
- 브랜드 owner/admin source: `brands/{brandID}/admins/{uid}.role in [owner, admin]`.
- legacy capability/UID 배열은 신규 권한 판단에 사용하지 않는다.
- 권한은 iOS 표시 조건만 믿지 않고 Functions와 rules에서 최종 검증한다.

### 브랜드 요청

- 앱은 `CloudFunctionsBrandRequestRepository`를 통해 callable을 사용한다.
- 사용자 요청과 관리자 group 상태는 별도 collection/projection으로 관리한다.
- 관리자 `rejected/completed` 목록은 `processedScope = recent | history`를 지원한다.
- 상세 데이터 계약: `docs/ai/DATA_SCHEMA.md`.

## Lookbook 삭제 lifecycle

### 읽기 순서

1. 제품/작업 결정: 관련 task `decisions.md`, ADR-018
2. 목록·soft delete·retry handler: `functions/src/lookbook/deletion/functions.ts`
3. purge orchestration: `functions/src/lookbook/deletion/purgeDrain.ts`
4. lease 정책: `functions/src/lookbook/deletion/purgeLease.ts`
5. query index: `firestore.indexes.json`
6. 권한: `firestore.rules`
7. 앱 연결: `CloudFunctionsLookbookDeletionRepository.swift` → `LookbookDeletionCloudFunctionsMapper.swift` → 공통 transport
8. 검증: 두 helper의 `*.test.ts`, task `qa-checklist.md`

### Soft delete와 목록

`functions/src/lookbook/deletion/functions.ts`에서 다음 이름을 찾는다.

- `requestBrandDeletion`, `cancelBrandDeletion`
- `softDeleteSeason`, `restoreSeason`, `batchSoftDeleteSeasons`
- `softDeletePost`, `restorePost`, `batchSoftDeletePosts`
- `listLookbookDeletionRequests`
- `retryFailedLookbookDeletionPurge`
- `onLookbookDeletionManualRetryQueued`

현재 계약:

- 앱 목록은 서버가 `active/failed`만 조회한다.
- 입력은 `targetType`, 선택적 `brandID`, `limit`, cursor다.
- `limit + 1`로 실제 다음 page가 있을 때만 `nextCursor`를 반환한다.
- 총 관리자만 failed manual retry token을 생성한다.
- trigger는 새 queued token만 처리하고 실패 시 scheduled fallback을 유지한다.

### Scheduled purge

`functions/src/lookbook/deletion/functions.ts`에서 다음 순서로 확인한다.

1. `expiredDeletionRequestPageLoader`: active/failed query와 cursor
2. `claimLookbookDeletionPurge`: 실행 직전 eligibility와 lease claim
3. `runLookbookDeletionPurge`: target별 Firestore/Storage 정리
4. `purgeClaimedLookbookDeletionRequest`: finalize와 실패 상태
5. `purgeExpiredLookbookDeletions`: target pass, drain 설정, 운영 로그

`lookbook/deletion/purgeDrain.ts`가 담당하는 순수 정책:

- active/failed 독립 page drain
- `brand -> season -> post` pass
- 같은 브랜드 순차 queue
- 서로 다른 브랜드 최대 3개 병렬
- 7분 이후 신규 claim 중단
- 실행 결과와 잔여 candidate 요약

`lookbook/deletion/purgeLease.ts`와 `lookbookDeletionPurgeLeases/{brandID}`가 scheduled/manual 상호 배제를 담당한다.

인덱스:

- active: `status + targetType + purgeAfter + requestID`
- failed: `status + autoRetryEligible + targetType + purgeAfter + retryAfter + requestID`

주요 완료 로그:

- `pageCount`, `loadedCount`, `startedCount`
- `successCount`, `failureCount`, `skippedCount`, `unstartedCount`
- `stopReason`, `hasRemainingCandidates`, `elapsedMillis`

운영/QA 상세는 `docs/ai/tasks/lookbook-deletion-purge-drain/progress.md`를 확인한다.

## URL 기반 시즌 import

### 구조 지도

| 책임 | 진입점 |
| --- | --- |
| Functions trigger/callable | `functions/src/lookbook/import/functions.ts` |
| 후보 discovery/parser | `functions/src/lookbook/import/seasonCandidateDiscovery.ts`, `seasonCandidateParser.ts` |
| Cloud Run package | `tools/lookbook-import-worker/` |
| HTTP server | `tools/lookbook-import-worker/src/server.ts` |
| 시즌 discovery | `tools/lookbook-import-worker/src/season-discovery.ts` |
| import 처리 | `tools/lookbook-import-worker/src/processor.ts` |
| extraction 결과·candidate evidence 계약 | `tools/lookbook-import-worker/src/extraction/core.ts` |
| source URL 마스킹·fingerprint | `tools/lookbook-import-worker/src/extraction/evidence.ts` |
| extractor/platform/domain version | `tools/lookbook-import-worker/src/extraction/version.ts` |
| Generic/Platform/Domain adapter registry | `tools/lookbook-import-worker/src/extraction/adapters/{registry,cafe24,types}.ts` |
| expected count/programmatic gallery | `tools/lookbook-import-worker/src/extraction/{expected-count,programmatic-gallery}.ts` |
| quality/canonical·content hash | `tools/lookbook-import-worker/src/extraction/{quality,dedupe}.ts` |
| existing post reconcile diff | `tools/lookbook-import-worker/src/extraction/reconcile.ts` |
| fixture manifest/corpus/differential | `tools/lookbook-import-worker/src/fixture/`, `tools/lookbook-import-worker/fixtures/` |
| lifecycle/retry | `job-lifecycle.ts`, `import-error.ts` |
| SSRF/HTTP 경계 | `public-http.ts` |
| Firebase/env 경계 | `firebase.ts`, `config.ts` |
| 아키텍처 | `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md` |

권장 흐름:

```text
앱이 candidate/import job 등록
→ Functions trigger가 Cloud Tasks enqueue
→ Cloud Tasks가 Cloud Run worker 호출
→ worker가 원본을 처리하고 Firestore/Storage 갱신
→ 앱이 job 상태와 생성 문서를 표시
```

진단 계약과 현재 상태는 `docs/ai/tasks/lookbook-import-diagnostics/`, `docs/ai/tasks/lookbook-import-worker/`, `docs/ai/tasks/lookbook-extraction-learning-loop/`의 `progress.md`를 확인한다. Phase 1부터 import job은 candidate evidence/version을 기록한다. Phase 2는 expected/programmatic evidence, quality, static/rendered/source/content-hash count를 추가했다. Phase 3의 `npm run test:fixtures`는 외부 fetch 없이 golden differential을 검증한다. Phase 4는 `needsReview` 결과를 materialization 전에 `awaitingReview`로 멈추고 아래 callable로 검토·재개한다.

- `getLookbookExtractionReview({brandID, jobID})`: 현재 generation/hash와 고정 후보를 조회한다.
- `reviewLookbookExtraction({brandID, jobID, reviewGeneration, reviewSnapshotHash, decision, excludedCandidateKeys?, expectedCandidateCount?, note?})`: 정상/오탐 제외/이미지 부족 결정을 generation별 audit로 기록한다.
- `requestLookbookExtractionReanalysis({brandID, jobID})`: 총 관리자만 correctionRequired job의 review/dispatch generation을 증가시켜 같은 job을 parsing부터 재실행한다.
- 안전한 정상 승인만 scoped trust baseline을 자동 등록한다. 별도 trust checkbox는 없고 review audit/trust baseline은 server-only다.
- Phase 5 evidence는 Worker가 전용 Storage prefix와 `lookbookExtractionEvidence` ledger에 7일 expiry로 저장하고 `lookbookExtractionIssueClusters`를 transaction 집계한다.
- `cleanupExpiredLookbookExtractionEvidence`는 매일 04:45 만료 ledger를 조회하고 결정적 `lookbook-extraction-evidence/{evidenceID}.json` path만 삭제한 뒤 성공한 ledger만 제거한다.
- Phase 6은 `requestLookbookSeasonRepair` → Worker generation별 diff → 변경이 있을 때만 `previewLookbookSeasonRepair` → generation/hash 기반 `applyLookbookSeasonRepair` 순서다. add/reorder/remove-candidate가 모두 0이면 audit `noChanges`와 job `succeeded/completed`로 종료하며 season/post를 쓰지 않는다. 적용 경로는 기존 season/post ID를 보존하고 삭제 후보를 자동 삭제하지 않는다.
- Phase 7은 discovery와 season-image 추출 전에 같은 adapter registry를 선택한다. Generic은 adapter 없이 동작하고 Cafe24 공통 section/noise 규칙은 `cafe24@1.0.0`에만 적용된다. 실제 domain adapter는 없으며 host와 등록된 fixture가 없는 domain 등록은 거부된다. job/diagnostic과 cache는 extractor `1.2.0` 및 전체 adapter version set을 사용한다.
- 2026-07-23 운영 worker `lookbook-import-worker-00016-thf`와 관련 Functions를 배포했다. YOUTH source job `MTTKsL7GJPY0VdrYqjmb`의 generation 1 preview `keep 1/add 45/reorder 0/remove 0`을 적용해 같은 season의 post를 46개로 복구했고 기존 `post_0000`을 유지했다. 세부 운영 증거는 task `progress.md`를 따른다.
- Phase 8에서 adapter registry 포함 worker를 `lookbook-import-worker-00018-zwl`로 운영 배포했다. rollback 기준은 `lookbook-import-worker-00017-stx`다. OUTSTANDING 운영 diagnostic은 static 12 → rendered/source 44와 `needsReview`, YOUTH 실제 URL read-only dry-run은 static 1 → source 46, HATCHINGROOM read-only dry-run은 static 후보 17을 확인했다. queue pending과 새 revision ERROR는 모두 0건이었다.
- 운영 bucket에는 2026-07-23 확인 기준 lifecycle rule이 없다. 기존 미디어에 영향을 주는 bucket 전역 정책 대신 위 scheduler를 사용한다.

## Firestore

### Rules

- 클라이언트 접근은 Firebase Auth UID와 authoritative admin/member 문서로 검증한다.
- 서버 전용 projection/audit/lease collection은 클라이언트 직접 접근을 차단한다.
- 시즌/포스트 hard delete는 앱에서 직접 수행하지 않는다.
- 변경 시 emulator 또는 deploy dry-run, diff check 후 승인된 범위만 배포한다.
- Firestore rules emulator package: `firestore-tests/`
- 문서 ID 경계 rules test: `firestore-tests/room-document-id.rules.test.mjs`
- 로컬 실행: `cd firestore-tests && npm install && npm test`
- `Rooms` create는 `ID`/`id`를 거부하고, update는 해당 필드 추가·변경·삭제를 거부하되 기존 legacy 값이 불변인 metadata update는 허용한다.
- rules 구현 진입점: `firestore.rules`의 `roomCreateHasNoDocumentIDFields`, `roomUpdateDoesNotChangeDocumentIDFields`, `match /Rooms/{roomID}`.
- 2026-07-14 Emulator 11/11과 dry-run 통과 후 `outpick-664ae`에 rules를 운영 배포했다.
- 같은 날 별도 승인된 Admin transaction으로 기존 Rooms 4건의 uppercase `ID`만 삭제했다. 사후 감사 기준 `Rooms.ID`/`Rooms.id` 보유 문서는 0건이다.

### Indexes

- query의 equality/range/orderBy 순서와 `firestore.indexes.json`을 함께 확인한다.
- 운영에만 존재하는 field override 삭제 경고가 있으면 `--force`를 임의 사용하지 않는다.
- index READY 확인이 선행되어야 하는 Functions query는 index 배포와 상태 확인 후 Functions를 배포한다.

## Firebase Storage

- root `firebase.json`의 Storage rules source는 `storage.rules`다.
- 기본 deny 후 path별 read/write 권한을 허용한다.
- Chat `rooms/{roomID}` write는 member/creator, profile write는 본인, Lookbook `brands/{brandID}` write는 총 관리자 또는 브랜드 owner/admin 기준이다.
- cross-service `firestore.get/exists`를 사용하는 rules는 Storage service agent의 Firestore Rules 권한도 확인한다.
- 운영 release ID, 과거 전역 허용 rules, 배포 당시 QA 상세는 task/운영 기록에서 확인하고 이 인덱스에는 복사하지 않는다.

검증 예시:

```bash
firebase deploy --only storage --project outpick-664ae --dry-run --non-interactive
git diff --check -- firebase.json storage.rules
```

실제 배포는 사용자 명시 승인 후 수행한다.

## 변경 시 하네스 갱신

- 코드 위치 변경: `docs/ai/ENTRYPOINTS.md`와 이 문서.
- 데이터/API 계약 변경: `docs/ai/DATA_SCHEMA.md`.
- 장기 선택 변경: ADR.
- phase 상태·배포·QA: 관련 task `progress.md`와 `qa-checklist.md`.
