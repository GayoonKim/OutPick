# Firebase Entrypoints

## 목적과 source of truth

Firebase 변경 시 Functions, Firestore, Storage의 실제 경계를 찾기 위한 인덱스다.

| 영역 | source of truth | workflow |
| --- | --- | --- |
| Functions | `functions/src/index.ts`, `functions/src/{core,shared,auth,brand,chat,lookbook,profile,styleMoods}/` | `.codex/skills/firebase-functions-workflow/SKILL.md` |
| Firestore rules | `firestore.rules` | `.codex/skills/firestore-workflow/SKILL.md` |
| Firestore indexes | `firestore.indexes.json` | `.codex/skills/firestore-workflow/SKILL.md` |
| Storage rules | `storage.rules`, root `firebase.json` | 배포 전 rules dry-run과 운영 권한 확인 |
| iOS callable transport | `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift` | 기능별 Repository/Client와 mapper를 함께 확인 |

- 운영 배포 revision과 일회성 QA 로그는 관련 task의 `progress.md`에 기록한다.
- 장기 기술 결정은 `docs/ai/ADR.md`, 데이터 계약은 `docs/ai/DATA_SCHEMA.md`를 확인한다.
- 데이터 삭제, rules 완화, 운영 배포 범위가 모호하면 구현/배포를 멈추고 사용자와 논의한다.

## iOS 환경별 Firebase 설정

- Development/Production 실제 plist는 각각 `LocalSecrets/Firebase/Development/GoogleService-Info.plist`, `LocalSecrets/Firebase/Production/GoogleService-Info.plist`에 보관하며 Git에서 제외한다.
- `Configurations/Development.xcconfig`는 `GayoonKim.OutPick.dev`와 `outpick-test`, `Configurations/Production.xcconfig`는 `GayoonKim.OutPick`과 `outpick-664ae`를 기대값으로 제공한다.
- `scripts/build/validate-and-copy-firebase-config.sh`는 선택된 plist의 `BUNDLE_ID`, `PROJECT_ID`, Google `CLIENT_ID/REVERSED_CLIENT_ID`를 build setting과 대조하고, 환경별 canonical Kakao Native App Key·callback scheme도 독립적으로 검증한다. Development↔Production 카카오 키·scheme을 함께 교차해도 Firebase 초기화 전에 빌드를 실패시킨다.
- 검증 fixture와 negative test는 `scripts/build/fixtures/GoogleService-Info-Fixture.plist`, `scripts/build/test-validate-and-copy-firebase-config.sh`다. fixture는 실제 credential이 아닌 테스트 전용 값만 포함한다.
- build phase가 검증을 통과한 단일 plist만 앱 번들의 `GoogleService-Info.plist`로 복사한다. 소스 트리의 plist를 target resource로 직접 포함하지 않는다.
- Development 실제 양성 빌드는 Firebase Console에 `GayoonKim.OutPick.dev` 앱을 등록하고 발급받은 plist를 설치한 뒤 수행한다. 콘솔 등록은 외부 상태 변경이므로 사용자 명시 요청 후 진행한다.
- runtime 검증은 `OutPick/App/Firebase/AppRuntimeConfiguration.swift`, 초기화는 `OutPick/App/AppDelegate.swift`가 담당한다. 기본 Firebase app은 검증된 plist로만 명시 구성한다.
- runtime은 xcconfig에서 받은 Kakao 실제값을 `OutPickEnvironment.expectedKakaoNativeAppKey`와 대조한다. build gate와 runtime에 둔 환경별 공개 키 상수는 설정 오조합을 두 단계에서 차단하기 위한 의도적 중복이다.
- 실제 Firebase UI test override 기본 경로도 `LocalSecrets/Firebase/Development/GoogleService-Info.plist`를 사용해 Development Bundle ID와 test project 조합을 유지한다.

## Functions 코드 지도

`functions/src/index.ts`는 현재 63개 배포 이름의 명시적 flat re-export만 가진다. 실제 handler와 helper는 아래 기능 module에서 찾는다.

Phase 4 구현 결과와 결정은 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-4-firebase-functions.md`, contract/service/policy 테스트는 `phase-4-firebase-functions-tests.md`와 `functions/src/**/*.test.ts`를 따른다.

Phase 6 전체 회귀와 운영 배포는 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-integration-tests.md`, `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-deployment.md`를 따른다. Functions는 Socket gate 통과 후 49개 export 전체를 배포하며 prior source rollback 기준을 확보하지 못하면 배포하지 않는다.

| 변경 목적 | 검색할 함수/파일 |
| --- | --- |
| 인증 | `functions/src/auth/functions.ts`, `kakaoService.ts`, `runtime.ts` |
| 총 관리자·브랜드 권한 | `functions/src/shared/brandAuthorization.ts` |
| 브랜드 요청 | `functions/src/brand/requests/functions.ts` |
| 브랜드 관리 | `functions/src/brand/admin/functions.ts`, `shared/brandValidation.ts` |
| 스타일 무드 관리 | `functions/src/styleMoods/{functions,repository,policy,contracts}.ts` |
| 브랜드·시즌 무드 할당 | `functions/src/shared/styleMoodAssignmentPolicy.ts`, `functions/src/lookbook/admin/seasonMoodFunctions.ts` |
| 계정·공개 프로필 | `functions/src/profile/{functions,profileTransaction,policy,contracts}.ts` |
| 계정 삭제 | `functions/src/accountDeletion/{functions,repository,policy,drain,cleanup,providerCleanup}.ts` |
| active 계정 guard | `functions/src/shared/accountStatus.ts` |
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

### 환경별 Kakao custom-token runtime

- `exchangeKakaoToken`의 handler와 runtime option은 `functions/src/auth/functions.ts`, Kakao 검증·Firebase custom-token 계약은 `kakaoService.ts`에서 찾는다.
- Firebase CLI가 제공하는 `GCLOUD_PROJECT` 계열 값에서 전용 service account를 정확히 결정하는 fail-closed 매핑은 `functions/src/auth/runtime.ts`, project 누락·미지원·교차 선택 회귀 테스트는 `runtime.test.ts`다. `serviceAccount` 옵션은 literal만 허용하므로 CEL parameter expression을 사용하지 않는다.
- Development runtime identity는 `outpick-auth-functions-dev@outpick-test.iam.gserviceaccount.com`, Production runtime identity는 `outpick-auth-functions-prod@outpick-664ae.iam.gserviceaccount.com`이며 이 함수 하나에만 연결한다.
- Token Creator는 project-level binding이 아니라 service account 자기 리소스에 대한 `roles/iam.serviceAccountTokenCreator` binding만 사용한다.
- service account 이메일을 `.env`에서 입력받지 않는다. `outpick-test`와 `outpick-664ae`만 각각의 canonical 계정으로 매핑하고 그 밖의 project는 유효한 runtime identity를 선택하지 않는다.
- Development 배포·검증 명령은 `firebase deploy --only functions:exchangeKakaoToken --project outpick-test`와 `gcloud functions describe exchangeKakaoToken --gen2 --region asia-northeast3 --project outpick-test`다.
- Production은 `firebase deploy --only functions:exchangeKakaoToken --project outpick-664ae --dry-run --non-interactive`로 사전 검증하고 사용자 명시 승인 후 실제 배포한다. 2026-08-03 revision `exchangekakaotoken-00042-geb`부터 Production 전용 identity를 사용한다.
- Simulator App Check debug token은 Firebase App Check API에 등록하되 원문을 Git, 하네스, 자동 runtime log에 기록하지 않는다. 재설치로 token이 바뀌면 기존 token을 폐기하고 새 token을 등록한다.

## 스타일 무드

- callable: `createStyleMood`, `updateStyleMood`, `updateSeasonMoods`.
- 권한: `brandAdmins/{uid}.isActive == true`인 총 관리자.
- 이름·alias 정책: `functions/src/styleMoods/policy.ts`.
- Firestore transaction과 term index 교체: `functions/src/styleMoods/repository.ts`.
- v1 56개 원본: `functions/seeds/style-moods.v1.json`.
- seed 실행기: `functions/scripts/seed-style-moods.mjs`.
- seed 기본은 dry-run이고 `--apply --project {projectID}`를 모두 명시해야 쓴다.
- 일반 클라이언트는 active `styleMoods`만 읽고 총 관리자는 inactive도 읽는다. 모든 클라이언트 쓰기와 `styleMoodTermIndex`/`styleMoodSeedMetadata` 접근은 금지한다.
- 브랜드 생성과 총 관리자 브랜드 수정은 active `moodIDs` 0~5개를 검증한다. 기존 시즌은 총 관리자 전용 `updateSeasonMoods`만 수정하며 모든 client season create/update를 거부한다.
- import worker가 생성하는 시즌은 `moodIDs: []`로 시작한다.
- rules/index 검증: `firestore-tests/style-moods.rules.test.mjs`, `run-firestore-tests.mjs`.
- 2026-07-28 `outpick-664ae`에 index·rules·Functions를 배포하고 v1 seed를 적용했다.
  - index `CICAgOi3voUK`: `READY`
  - `createStyleMood` revision `createstylemood-00001-zip`: `ACTIVE`
  - `updateStyleMood` revision `updatestylemood-00001-vuv`: `ACTIVE`
  - seed hash `3a83ea71f06ce096672021e06e6112593a974fa0901bf35e6088651f63b40177`
  - 사후 dry-run은 create/update/upsert/delete 0건이다.
- 2026-08-03 `outpick-test`에도 동일 v1 seed를 적용했다.
  - 무드 56개, `styleMoodTermIndex` 137개, metadata version 1/count 56
  - content hash `3a83ea71f06ce096672021e06e6112593a974fa0901bf35e6088651f63b40177`
  - 사후 dry-run create/update/upsert/delete 0건, 실제 Kakao 신규 사용자 온보딩 완료 확인

## 계정과 공개 프로필

- callable: `checkNicknameAvailability`, `completeOnboarding`, `updatePublicProfile`, `updateStylePreferences`.
- 비공개 계정: `users/{uid}`. 본인 read, 모든 client write 금지.
- 공개 프로필: `userPublicProfiles/{uid}`. active 조회자가 active 대상만 read하며 모든 client write 금지.
- 닉네임 충돌 인덱스: 서버 전용 `nicknameIndex/{sha256(normalizedNickname)}`.
- `checkNicknameAvailability`는 인증 사용자에게 가용성만 반환하며 닉네임을 예약하지 않는다.
- `completeOnboarding`은 비공개 계정·공개 프로필·닉네임 인덱스를 한 transaction으로 생성한다.
- 관심 무드는 1~5개의 고유한 active `styleMoods`만 허용한다.
- `updatePublicProfile`은 기존/신규 닉네임 인덱스를 한 transaction으로 교체한다.
- 프로필 이미지 Storage 쓰기는 owner이며 `users.accountStatus == active`일 때만 허용한다.
- 신규 온보딩 아바타는 계정 생성 후 업로드하고 `updatePublicProfile`로 경로를 기록한다.
- 이메일 기반 관리자 지정은 `firebaseAuth.getUserByEmail`을 사용하며 Firestore `users.email` query를 사용하지 않는다.
- 검증: `functions/src/profile/*.test.ts`, `functions/src/shared/accountStatus.test.ts`, `firestore-tests/profile*.test.mjs`.
- 2026-07-28 Phase 3 앱 호환 전환과 자동 검증 후 `outpick-664ae`에 Functions·Firestore rules·Storage rules를 운영 배포했다.
- `firebase functions:list`에서 네 callable 모두 v2, `asia-northeast3`, Node.js 24로 등록됨을 확인했다. `checkNicknameAvailability`는 2026-07-28 운영 create operation까지 완료했다.
- iOS 연결은 `CloudFunctionsProfileMutationRepository`, `CheckNicknameAvailabilityUseCase`, `CompleteOnboardingUseCase`를 사용한다.

## Phase 7 계정 삭제 서버

- callable: `prepareAccountDeletion`, `requestAccountDeletion`, `cancelAccountDeletion`, `getAccountDeletionStatus`.
- scheduler: `finalizeExpiredAccountDeletions`, 매시 정각, `asia-northeast3`.
- 요청은 최근 인증, App Check, 5분 TTL 일회성 intent를 요구한다.
- 요청 transaction은 `users.accountStatus = deletionPending`과 삭제 요청/outbox를 원자 생성하고 refresh token revoke를 수행한다.
- 취소는 서버 시각이 `cancelableUntil`보다 이른 `grace` 상태에서만 성공한다.
- worker는 UID + `accountGenerationID`, lease, stage를 검증하고 공개 프로필·engagement·댓글·메시지/reply preview·방·역할·개인 상태·provider/Auth 순으로 정리한다.
- Socket은 handshake에서 active 상태를 확인하고 연결 뒤 사용자 문서 listener가 pending/missing 상태를 감지하면 fail closed로 연결을 종료한다.
- 서버 전용 컬렉션: `accountDeletionIntents`, `accountDeletionRequests`, `accountDeletionNotificationOutbox`, `completedDeletionSuppressions`, `accountDeletionAuditLogs`.
- 필수 Secret: `KAKAO_ADMIN_KEY`, `ACCOUNT_DELETION_LEDGER_HMAC_KEY`.
- 검증: Functions 97/97, Socket 64/64, Rules 26/26, account/profile transaction 7/7.
- iOS App Check 진입점:
  - `OutPick/App/Firebase/OutPickAppCheckProviderFactory.swift`
  - 시뮬레이터는 Debug Provider, 모든 실기기는 App Attest를 사용한다.
  - `AppDelegate.configureFirebaseApp`이 `FirebaseApp.configure`보다 먼저 Provider Factory를 등록한다.
  - `OutPick/OutPick.entitlements`의 App Attest environment는 Firebase 요구에 따라 `production`이다.
- 2026-07-29 부분 운영 반영:
  - Secret Manager API 활성화, `ACCOUNT_DELETION_LEDGER_HMAC_KEY` 생성
  - 계정 삭제 TTL 4개 `ACTIVE`
  - Firestore rules/indexes와 Storage rules 배포
  - Socket `outpick-socket-00008-4wl` traffic 100%, `/readyz` 정상, 배포 직후 ERROR 0건
- 출시 전 보류 상태:
  - PITR 비활성, 예약 백업 0개, Storage soft delete 7일
  - Production Kakao 실제 로그인은 callback → `exchangeKakaoToken` HTTP 200 → 기존 프로필 복원 → 앱 로그아웃까지 완료했고 기존 Auth/Firestore를 보존했다.
  - Production Google 실제 로그인과 provider별 계정 삭제 요청·취소 재인증 smoke는 미완료
  - Apple Developer Program 가입 후 Team ID 발급·Firebase App Attest 등록·지원되는 iPhone 실기기 검증
  - 실제 앱 출시 게이트에서 PITR·예약 백업·30일 soft delete·별도 export/복구 훈련을 적용·검증한다.
- 2026-07-29 운영 반영:
  - HMAC·Kakao Secrets version 1 enabled
  - 계정 삭제 callable 4개와 hourly finalizer 배포
  - 공식 App Check Debug Token API로 현재 iOS Simulator token 등록
  - Debug Token 원문은 저장소·하네스·채팅에 기록하지 않는다.

## Development Socket runtime

- `outpick-test` Cloud Run `outpick-socket-development`는 전용 service account로 Firebase Admin ADC를 사용한다.
- Storage bucket은 `OUTPICK_FIREBASE_STORAGE_BUCKET=outpick-test.firebasestorage.app`으로 명시하며 운영 bucket 기본값 사용을 금지한다.
- service account의 Storage 객체 권한은 Development bucket 하나에만 부여한다.
- Cloud Run transport는 iOS 접속을 허용하지만 Socket.IO handshake에서 Development Firebase ID Token과 active account를 검증한다.
- Socket 전용 App Check 검증은 아직 없으며 별도 보안 강화 후보다.

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
| Cloud Run IAM·경로별 OIDC 검증 | `tools/lookbook-import-worker/src/oidc-auth.ts`, `config.ts` |
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
- Phase 8 종료 후 YOUTH 신규 등록 discovery 회귀 보완은 Cafe24 `collection_detail.html` underscore 경로를 공통 후보로 인정하고 extractor를 `1.2.1`로 올렸다. 현재 공개 YOUTH 목록 HTML에서 정적 후보 20개를 확인하고 worker `lookbook-import-worker-00019-ftd`를 Ready/traffic 100%로 운영 배포했다. startup probe·port listen, ERROR 0건, queue task 0건을 확인했다. 별도 Cloud Tasks health 요청은 인증 계층 404로 container request log에 도달하지 않아 임시 task를 모두 삭제했지만, 이후 사용자 수동 QA에서 실제 앱의 YOUTH 시즌 추출 목록이 정상 표시돼 callable→worker→후보 저장·표시 경로를 확인했다.
- extractor `1.2.2`부터 review quality는 content-hash 최종 후보 수와 expected-count evidence를 비교한다. 일치+hash 완료는 첫 signature도 자동 진행하고, 예상 수 미확인·수량 불일치·hash 미완료만 `awaitingReview`에 남긴다. raw/static/rendered/final count는 계속 job evidence로 저장한다.
- extractor `1.2.2` worker `lookbook-import-worker-00021-ghs`는 Ready/traffic 100%, startup probe·port 8080 listen, recent ERROR 0건이며 queue는 RUNNING/pending 0건이다. rollback revision은 `lookbook-import-worker-00019-ftd`다.
- extractor `1.2.3`은 script 전체의 `total`을 모으지 않고 현재 HTML에 존재하는 gallery element ID와 같은 config block만 declared evidence로 사용한다. programmatic gallery 밖 정적 후보 수도 별도 scoped evidence로 더해 YOUTH Spring 2nd `45+1=46`, Summer `42+7=49`를 표현한다.
- extractor `1.2.3` worker `lookbook-import-worker-00022-5gn`은 Ready/Active·traffic 100%, container healthy 2.05초, recent ERROR 0건이며 queue는 RUNNING/pending 0건이다. rollback revision은 `lookbook-import-worker-00021-ghs`다.
- 2026-07-28 Phase 5 시즌 기본 `moodIDs: []` materialization을 포함한 worker `lookbook-import-worker-00023-879`을 운영 배포했다. Ready/traffic 100%, container healthy 1.88초, recent ERROR 0건과 queue task 0건을 확인했으며 rollback revision은 `lookbook-import-worker-00022-5gn`이다.
- 2026-08-01 Development 전용 worker `lookbook-import-worker-development-00003-5kc`를 `outpick-test`에 배포하고 worker 의존 Functions 15개를 연결했다. Cloud Run은 비공개 IAM으로 task service account만 직접 호출할 수 있고, worker가 Google OIDC의 서명·만료·issuer·audience·검증된 email을 다시 확인한다. `/tasks/import-job`은 task service account, `/wake`와 `/tasks/discover-seasons-diagnostic`은 Functions runtime service account만 허용한다. `/readyz` Cloud Tasks OIDC 200, task identity의 빈 import payload 500, Functions identity의 빈 diagnostic payload 500, Functions identity의 import 경로 403으로 transport·앱 인증·경로 분리를 확인했다.
- 2026-08-03 W3C 전용 sample로 실제 trigger → Cloud Tasks → worker → review → materialization smoke를 완료했다. job은 `succeeded`, post 5개, asset 6/6 `ready`, worker ERROR 0건이었고 smoke 브랜드·Storage 12개·evidence/issue cluster는 검증 후 삭제해 잔존 0건을 확인했다.
- Worker 배포에는 `OUTPICK_IMPORT_OIDC_AUDIENCE`, `OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL`, `OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL`이 필수다. worker는 `OUTPICK_FIREBASE_PROJECT_ID`별 canonical audience·task 계정·Functions 계정의 정확한 조합만 허용해 Development/Production 값 교차 주입과 임의의 유효한 계정을 시작 전에 거부한다.
- 운영 bucket에는 2026-07-23 확인 기준 lifecycle rule이 없다. 기존 미디어에 영향을 주는 bucket 전역 정책 대신 위 scheduler를 사용한다.

## Firestore

### Rules

- 클라이언트 접근은 Firebase Auth UID와 authoritative admin/member 문서로 검증한다.
- 서버 전용 projection/audit/lease collection은 클라이언트 직접 접근을 차단한다.
- 시즌/포스트 hard delete는 앱에서 직접 수행하지 않는다.
- 변경 시 emulator 또는 deploy dry-run, diff check 후 승인된 범위만 배포한다.
- Firestore rules emulator package: `firestore-tests/`
- 문서 ID 경계 rules test: `firestore-tests/room-document-id.rules.test.mjs`
- 스타일 무드 rules test: `firestore-tests/style-moods.rules.test.mjs`
- 로컬 실행: `cd firestore-tests && npm install && npm test`
- 위 실행은 style mood seed의 빈 DB dry-run → Emulator apply → 재-dry-run 변경 0건도 함께 검증한다.
- `Rooms` create는 `ID`/`id`를 거부하고, update는 해당 필드 추가·변경·삭제를 거부하되 기존 legacy 값이 불변인 metadata update는 허용한다.
- rules 구현 진입점: `firestore.rules`의 `roomCreateHasNoDocumentIDFields`, `roomUpdateDoesNotChangeDocumentIDFields`, `match /Rooms/{roomID}`.
- 2026-07-14 Emulator 11/11과 dry-run 통과 후 `outpick-664ae`에 rules를 운영 배포했다.
- 같은 날 별도 승인된 Admin transaction으로 기존 Rooms 4건의 uppercase `ID`만 삭제했다. 사후 감사 기준 `Rooms.ID`/`Rooms.id` 보유 문서는 0건이다.

### Indexes

- query의 equality/range/orderBy 순서와 `firestore.indexes.json`을 함께 확인한다.
- 운영에만 존재하는 field override 삭제 경고가 있으면 `--force`를 임의 사용하지 않는다.
- index READY 확인이 선행되어야 하는 Functions query는 index 배포와 상태 확인 후 Functions를 배포한다.
- 2026-07-29 Phase 6 관심 스타일 브랜드용 `brands(moodIDs ARRAY_CONTAINS, likeCount DESC, __name__ ASC)` index `CICAgLiT_JAK`를 `outpick-664ae`에 배포하고 `READY`를 확인했다. 기존 운영 field override 1개는 `--force` 없이 보존했다.

## Firebase Storage

- root `firebase.json`의 Storage rules source는 `storage.rules`다.
- 브랜드 asset write는 `users/{uid}`와 `brandAdmins/{uid}` 또는 `brands/{brandID}/admins/{uid}` 두 문서만 교차 조회한다. Storage rules는 한 번의 평가에서 Firestore 문서를 최대 2개만 조회할 수 있으므로 `brands/{brandID}` 존재 확인을 추가하지 않는다.
- 브랜드 생성 로고 계약은 `thumb.jpg`·`detail.jpg` 업로드 후 `updateBrandLogoPaths`로 두 경로를 함께 패치한다. 앱은 완료를 기다리며 실패 시 생성 문서를 재사용해 재시도한다.
- 기본 deny 후 path별 read/write 권한을 허용한다.
- Chat `rooms/{roomID}` write는 member/creator와 active 계정, profile write는 owner와 active 계정, Lookbook `brands/{brandID}` write는 총 관리자 또는 브랜드 owner/admin 기준이다.
- cross-service `firestore.get/exists`를 사용하는 rules는 Storage service agent의 Firestore Rules 권한도 확인한다.
- 운영 release ID, 과거 전역 허용 rules, 배포 당시 QA 상세는 task/운영 기록에서 확인하고 이 인덱스에는 복사하지 않는다.

검증 예시:

```bash
firebase deploy --only storage --project outpick-664ae --dry-run --non-interactive
git diff --check -- firebase.json storage.rules
```

실제 배포는 사용자 명시 승인 후 수행한다.

## 브랜드·채팅 개발 데이터 선택 초기화

- 순수 삭제 범위·project/hash/apply gate: `functions/src/developmentReset/brandChatManifest.ts`
- 읽기 전용 manifest: `npm run audit:brand-chat-reset -- --project outpick-test`
- 실제 삭제: `npm run reset:brand-chat-data -- --apply --project outpick-test --confirmation-hash HASH`
- reset gate는 `outpick-test`와 `outpick-test.firebasestorage.app`만 허용하며 운영 project `outpick-664ae`는 테스트로 명시적으로 거부한다.
- Auth, 사용자 계정/공개 프로필/관심 스타일, 총 관리자, 스타일 무드는 보존한다.
- 브랜드·룩북·채팅 root/하위 문서와 관련 Storage/user projection만 삭제한다.
- 실제 삭제는 미분류 root collection 0개, queue `PAUSED`, task 0개, 최신 hash와 별도 사용자 승인을 모두 요구한다.

## 변경 시 하네스 갱신

- 코드 위치 변경: `docs/ai/ENTRYPOINTS.md`와 이 문서.
- 데이터/API 계약 변경: `docs/ai/DATA_SCHEMA.md`.
- 장기 선택 변경: ADR.
- phase 상태·배포·QA: 관련 task `progress.md`와 `qa-checklist.md`.
