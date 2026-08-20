# Firebase Entrypoints

## 목적과 source of truth

Firebase 변경 시 Functions, Firestore, Storage의 실제 경계를 찾기 위한 인덱스다.

| 영역 | source of truth | workflow |
| --- | --- | --- |
| Functions | `functions/src/index.ts`, `functions/src/{core,shared,auth,brand,chat,lookbook,profile,styleMoods}/` | `.codex/skills/firebase-functions-workflow/SKILL.md` |
| Firestore rules | `firestore.rules` | `.codex/skills/firestore-workflow/SKILL.md` |
| Firestore indexes | `firestore.indexes.json` | `.codex/skills/firestore-workflow/SKILL.md` |
| Storage rules | 기본 bucket `storage.rules`; Phase 7 Quarantine 전용 bucket `storage.chat-media-quarantine.rules` | bucket target 연결 후 rules dry-run과 운영 권한 확인 |
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
| Chat media v2 queue·dispatcher·watchdog·ready cleanup | `functions/src/chat/media/{contracts,functions,orchestrationService,readyService}.ts` |

기본 검증:

```bash
cd functions
npm test
npm run lint
npm run build
```

운영 배포는 사용자 승인 후 workflow가 지정한 명령을 사용한다.

### Chat media Phase 7.1 환경 계약

- Socket: `CHAT_MEDIA_QUARANTINE_BUCKET`.
- Functions queue trigger/dispatcher: `CHAT_MEDIA_DISPATCHER_URL`, `CHAT_MEDIA_IMAGE_TASKS_QUEUE`, `CHAT_MEDIA_VIDEO_TASKS_QUEUE`, `CHAT_MEDIA_TASKS_SERVICE_ACCOUNT_EMAIL`, 선택 `CHAT_MEDIA_DISPATCHER_AUDIENCE`, `CHAT_MEDIA_IMAGE_SERVICE_URL`, 선택 `CHAT_MEDIA_IMAGE_SERVICE_AUDIENCE`, `CHAT_MEDIA_VIDEO_JOB_NAME`, `CHAT_MEDIA_QUARANTINE_BUCKET`. Gen2 private dispatcher와 이미지 Service의 URL/audience는 IAM 보호 대상인 실제 `run.app` service URI를 사용한다.
- Cloud Run worker: 이미지 Service는 인증된 `POST /process` body로 upload path·lease token을 받고, 영상 Job은 dispatcher override의 `CHAT_MEDIA_UPLOAD_PATH`, `CHAT_MEDIA_LEASE_TOKEN`, `CHAT_MEDIA_KIND`를 사용한다. 둘 다 고정 env `CHAT_MEDIA_READY_BUCKET`을 가진다.
- Development `outpick-test`에는 Quarantine `outpick-test-chat-media-quarantine`과 일반 media `outpick-test-chat-media` bucket을 분리했다. Quarantine은 `asia-northeast3` Standard, soft delete/versioning off, age 1 lifecycle이며 일반 media는 실제 `display/thumbnail` 저장소다. Firebase Storage target은 각각 `chatMediaQuarantine`, `chatMediaReady`다.
- Production canonical 자원명은 Quarantine `outpick-664ae-chat-media-quarantine`, ready `outpick-664ae-chat-media`, image Service `outpick-chat-media-image`, video Job `outpick-chat-media-video`, queue `chat-media-image-processing`/`chat-media-video-processing`, identity `outpick-chat-media-orchestrator`/`outpick-chat-media-cleanup`/`outpick-chat-media-worker`/`outpick-chat-media-task`다. 생성·IAM·배포 순서와 rollback은 `docs/ai/runbooks/CHAT_MEDIA_PRODUCTION_ROLLOUT.md`를 따른다.
- 기본 bucket Rules와 Emulator는 root `firebase.json`을 사용한다. Phase 7 전용 bucket은 `firebase.chat-media.json`의 target config로 분리하며 Development ready Rules는 `firebase deploy --config firebase.chat-media.json --only storage:chatMediaReady --project outpick-test`로 배포한다. 이 config를 지정하지 않으면 전용 target은 배포 대상에 포함되지 않는다.
- Development queue는 `chat-media-image-processing`, `chat-media-video-processing`이고 모두 max concurrent 1/QPS 1이다. Job은 `outpick-chat-media-image-development`(timeout 2400초)와 `outpick-chat-media-video-development`(timeout 720초)이며 2 vCPU·1 GiB, task/parallelism 1, retry 0을 사용한다.
- Development 전용 identity는 orchestrator `outpick-chat-media-orch-dev`, cleanup `outpick-chat-media-cleanup-dev`, worker `outpick-chat-media-worker-dev`, task `outpick-chat-media-task-dev`다. orchestrator·cleanup에는 Firestore trigger 수신을 위해 project-level `roles/eventarc.eventReceiver`와 각자 전달하는 trigger Run service 한정 `roles/run.invoker`를 부여했다. task identity는 dispatcher Run service 한정 `roles/run.invoker`를 가진다. Gen2 Function 재배포가 underlying Run service의 수동 invoker binding을 제거할 수 있으므로 media Functions 배포 뒤 이 exact binding을 반드시 재감사한다. orchestrator는 이미지 Service 한정 `roles/run.invoker`와 영상 Job 한정 `roles/run.jobsExecutorWithOverrides`를 사용해야 한다. Socket identity에는 Tasks/Run Admin을 부여하지 않으며 Quarantine bucket 한정 `roles/storage.objectUser`와 자기 서비스 계정 한정 `roles/iam.serviceAccountTokenCreator`를 사용해 signed PUT target 발급·cleanup과 V4 `signBlob`을 수행한다.
- worker image는 `asia-northeast3-docker.pkg.dev/outpick-test/outpick-runtime/chat-media-processing-worker@sha256:4741213f15d40de2ba8d916203df6f57523c2133fcbd4da6a4d34de687d56a4f`다. image/video Development Job 모두 같은 digest를 사용한다. Production bucket/IAM/queue/Job은 변경하지 않았다.

### Chat media Phase 7.2 서버 진입점

- `onChatMediaWorkerCompleted`: normalized manifest 최초 기록을 감지해 ready transaction을 수행한다.
- `reconcileChatMediaObjectCleanup`: 15분마다 terminal `MediaUploads.cleanupStatus`를 수렴시킨다.
- `chatMediaDeliveryJobs`: client deny, Socket Admin SDK watcher 전용이며 `expiresAt` 7일 TTL이다.
- 일반 media `storage.rules`: `attachments/{attachmentID}/{display|thumbnail}`은 account capability와 대응 visible v2 message 두 문서만 조회해 `readyAttachmentIDs`를 확인한다. message 없는 staging·고아 객체, 삭제·비노출 message, 비활성 account는 읽을 수 없다.
- Development에는 관련 Firestore/Storage Rules, media exact composite index 4개, `MediaUploads.expiresAt`·`chatMediaDeliveryJobs.expiresAt` TTL과 Phase 7.1/7.2 Function 9개를 반영했다. 두 Firestore trigger를 포함한 Function은 모두 `ACTIVE`다. 배포 후 기존 cleanup scheduler 감사에서 원격에만 빠져 있던 `chatMessageCleanupJobs(status, nextAttemptAt)`, `moderationRoomCleanupJobs(status, nextAttemptAt)` manifest index 2개도 exact 생성해 `READY`로 만들었고 다음 자동 실행은 HTTP 200이었다. Production은 변경하지 않았다.

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
  - Debug 구성은 시뮬레이터와 실기기 모두 Debug Provider를 사용하고 `OutPick.Debug.entitlements`에서 App Attest entitlement를 제외한다.
  - Release 구성은 시뮬레이터에서 Debug Provider를 유지하고, 실기기에서 App Attest와 `OutPick.entitlements`를 사용한다.
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
  - Production Google·Kakao active 로그인 → 메인 탭 → 기본 read/write smoke는 2026-08-08 완료했다. provider별 계정 삭제 요청·취소 재인증 smoke는 출시 전 QA로 남긴다.
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
- 2026-08-18 Phase 6 Development rollout에서 `createComment`·`createReply`, Firestore Rules와 `moderationCommentWriteRateLimitBuckets.expiresAt` exact TTL을 반영했다. 전체 index manifest는 Development 원격 전용 composite 2개 삭제 위험 때문에 배포하지 않았다.
- 첫 방 생성 수동 QA에서 Development의 구버전 `getMyModerationState`가 `moderationAccounts.accountStatus`를 쓰지 않아 최신 Rules의 `isAccountActive()`가 생성을 거부하는 버전 불일치를 확인했다. 최신 함수는 `users.accountStatus`를 projection에 포함하므로 코드 변경 없이 해당 함수만 2026-08-18 Development exact target으로 재배포했다. 앱 bootstrap 재호출이 기존 누락 projection을 자동 보정한다.
- 방 생성 성공 후 오픈채팅 목록의 `isClosed + lifecycleStatus + lastMessageAt desc` composite가 Development에 없어 원격 쿼리가 `FAILED_PRECONDITION`으로 실패했다. 전체 index manifest 대신 해당 index `CICAgOi3z5wK` 하나만 exact 생성해 기존 원격 전용 index를 보존했으며, `READY` 후 동일 쿼리의 실제 방 반환을 확인했다.
- Socket revision `outpick-socket-development-00004-rud`, image digest `sha256:4e2c78775ad7d066e29bf0a87abbc463e49074941e3dc8982f281a06d96870d2`가 traffic 100%이며 이전 `00002-hal`은 rollback이다. canonical readiness 200, 배포 후 ERROR 0건이다.

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
| 시즌 대표 이미지 보강 Phase 7 | `tools/lookbook-import-worker/src/extraction/{image-candidates,season-cover}.ts`, `season-discovery.ts`, `season-discovery-processor.ts` |
| durable 시즌 discovery 접수/dispatch/watchdog/review | `functions/src/lookbook/import/seasonDiscoveryJobs.ts`, `functions/src/shared/seasonDiscoveryCreation.ts` |
| durable 시즌 discovery Worker/publish/동일성 | `tools/lookbook-import-worker/src/season-discovery-processor.ts`, `season-identity.ts`, `server.ts`의 `/tasks/discover-seasons` |
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

durable 시즌 discovery의 enqueue 완료 기록은 job을 transaction으로 다시 읽어 같은 `queued` generation/dispatch generation일 때만 `dispatching`으로 전이한다. Worker가 먼저 완료한 상태를 trigger가 되돌리지 않는다. 새 generation 접수·재분석은 기존 published pointer를 즉시 무효화하고, candidate import/asset retry는 실제 mutation transaction 안에서 현재 published snapshot 동일성을 재검증한다.

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
- `retryLookbookExtractionAfterFix({brandID, jobID})`: 총 관리자라도 `fixed` issue와 검증된 상위 동일-stage runtime이 있는 correctionRequired job만 review/dispatch generation을 증가시켜 다시 실행한다. Production legacy `requestLookbookExtractionReanalysis`는 2026-08-06 삭제했다.
- 안전한 정상 승인만 scoped trust baseline을 자동 등록한다. 별도 trust checkbox는 없고 review audit/trust baseline은 server-only다.
- Phase 5 evidence는 Worker가 전용 Storage prefix와 `lookbookExtractionEvidence` ledger에 7일 expiry로 저장한다. Phase 2 issue operations recorder는 로직 불충분만 `lookbookExtractionIssueClusters`에 transaction 집계하고 job projection을 함께 기록한다.
- `cleanupExpiredLookbookExtractionEvidence`는 매일 04:45 만료 ledger의 결정적 occurrence object를 먼저 삭제하고, terminal `expiresAt`이 지난 cluster의 현재 대표 object를 먼저 삭제한 뒤 성공한 Firestore 문서만 제거한다.
- Phase 6은 `requestLookbookSeasonRepair` → Worker generation별 diff → 변경이 있을 때만 `previewLookbookSeasonRepair` → generation/hash 기반 `applyLookbookSeasonRepair` 순서다. add/reorder/remove-candidate가 모두 0이면 audit `noChanges`와 job `succeeded/completed`로 종료하며 season/post를 쓰지 않는다. 적용 경로는 기존 season/post ID를 보존하고 삭제 후보를 자동 삭제하지 않는다.
- Phase 7은 discovery와 season-image 추출 전에 같은 adapter registry를 선택한다. Generic은 adapter 없이 동작하고 Cafe24 공통 section/noise 규칙은 `cafe24@1.0.1`에만 적용된다. 실제 domain adapter는 없으며 host와 등록된 fixture가 없는 domain 등록은 거부된다. job/diagnostic과 cache는 extractor `1.2.3` 및 전체 adapter version set을 사용한다.
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
- 2026-08-03 PR #3 head `5a61d1f`의 Production candidate `lookbook-import-worker-00024-fow`를 traffic 0%로 배포해 canonical task/Functions OIDC route smoke를 통과했다. PR #3 merge commit `7383a0e`의 tree가 candidate source와 동일함을 확인한 뒤 traffic을 100%로 전환했다. W3C 전용 Production import는 trigger → Cloud Tasks → worker → review → materialization에서 `succeeded`, post 5개, asset 6/6 `ready`였고 전환 후 ERROR·queue pending 0건을 확인했다. smoke Firestore tree·Storage 12개·evidence ledger/JSON·단독 issue cluster는 삭제해 잔존 0건이다. rollback은 `lookbook-import-worker-00023-879`이다.
- Worker 배포에는 `OUTPICK_FIREBASE_STORAGE_BUCKET`, `OUTPICK_IMPORT_OIDC_AUDIENCE`, `OUTPICK_IMPORT_TASKS_SERVICE_ACCOUNT_EMAIL`, `OUTPICK_IMPORT_FUNCTIONS_SERVICE_ACCOUNT_EMAIL`이 필수다. worker는 `OUTPICK_FIREBASE_PROJECT_ID`별 canonical Storage bucket·audience·task 계정·Functions 계정의 정확한 조합만 허용해 Development/Production 값 교차 주입과 임의의 유효한 값을 시작 전에 거부한다.
- Worker 배포는 `scripts/ai/deploy-lookbook-import-worker.sh {development|production} --plan`으로 계약을 먼저 확인한다. 실제 배포는 사용자 승인 후 `--deploy-candidate`로 traffic 0% revision만 만들며, 검증·전환·rollback은 `docs/ai/runbooks/LOOKBOOK_IMPORT_WORKER_DEPLOYMENT.md`를 따른다.
- Development/Production candidate QA는 `gayunkim.1@gmail.com`에 각 환경의 Functions 기본 Compute 계정과 Lookbook task 계정 exact 리소스의 `roles/iam.serviceAccountOpenIdTokenCreator`만 영구 부여한다. 운영 CLI도 환경별 exact operator service account에 같은 좁은 역할로 IAM Credentials `generateIdToken`을 직접 호출한다. 전체 access token/JWT/blob 서명이 가능한 사용자 `roles/iam.serviceAccountTokenCreator`와 서비스 계정 key는 사용하지 않는다.
- 운영 bucket에는 2026-07-23 확인 기준 lifecycle rule이 없다. 기존 미디어에 영향을 주는 bucket 전역 정책 대신 위 scheduler를 사용한다.

## Firestore

### 전역 사용자 차단

- owner-only source는 `users/{uid}/blockedUsers/{blockedUID}`이며 기존 Rules로 본인 read만 허용하고 client write는 막는다. 이번 Phase 4에는 Rules/index 변경이 없다.
- callable `blockUser`/`unblockUser`는 `functions/src/lookbook/safety/blockContracts.ts`의 exact payload 검증과 `functions.ts`의 인증 UID 권위 mutation을 사용한다. 자기 차단과 unknown field를 거부하고 차단 최초 `createdAt`을 보존한다.
- iOS 서버 최신화는 본인 blockedUsers collection을 직접 읽고, 룩북 hidden author 조회는 더 이상 `blockingMe` collection-group을 합치지 않는다.
- Socket push는 `Socket/src/push/chatPushService.js`가 recipient의 blockedUsers relation을 전송 직전에 조회한다. 조회 실패도 해당 recipient에 대해 fail closed하며 room broadcast 자체는 유지한다.

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
- Development `outpick-test`에서는 `service-86635107099@gcp-sa-firebasestorage.iam.gserviceaccount.com`에 `roles/firebaserules.firestoreServiceAgent`가 필요하다. 이 역할이 없으면 Auth·App Check·Firestore 문서가 정상이더라도 Storage rules의 교차 조회가 실패해 브랜드 로고 업로드가 403으로 거부된다.
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
- 시즌 목록 discovery는 이미지 import와 분리된 `lookbook-discovery-jobs` queue를 사용한다. `createBrand` transaction이 최초 job을 만들며, 수동 요청은 같은 fingerprint의 active job에 coalesce된다. Worker는 lease와 generation을 재검증하고 candidate snapshot 전체 저장 뒤 brand published pointer를 전환한다.
- 2026-08-05 Development 최신 배포 기준 Worker는 `lookbook-import-worker-development-00012-fih` traffic 100%, 직전 rollback은 `00010-hiq`다. runtime은 source `3597b2b359c8c012258dc31acd55a5e5833cfafb`, discovery contract 3, image extractor 1.2.3, Cafe24 adapter 1.0.1이며 전환 후 ERROR 0건·두 queue task 0건을 확인했다. discovery queue는 초당 1건·동시 1건·최대 3회다.
- 2026-08-05 AMOMENTO Cafe24 모달 목록 보강은 새 시즌 discovery job과 Worker runtime을 `contract:2`로 맞춘다. `functions/src/shared/seasonDiscoveryCreation.ts`가 새 job 계약을, `scripts/ai/deploy-lookbook-import-worker.sh`가 Worker 환경 계약을 소유한다. Development 실제 공개 URL smoke 15개로 cluster를 `fixed`로 열고, 총 관리자 Simulator 재시도 job `eK2fR8yhIZQ23gNDKuVs`가 후보 15개·contract 2로 성공해 cluster `verified` version 6을 확인했다. Production은 변경하지 않았다.
- Phase 7은 모든 브랜드에 `목록 대표 이미지 우선 → 시즌 상세 콘텐츠 영역의 최상단 첫 유효 이미지 fallback`을 `contract:3`으로 묶는다. Functions canonical revision과 Worker 배포 script를 함께 3으로 올리고 candidate provenance/job 집계/snapshot hash를 연결했다. 최종 Worker 115/115·fixture 9/9·Functions 146/146과 각 lint/build가 통과했으며 Development AMOMENTO 후보·대표 이미지 15/15와 앱 표시를 확인했다. Production과 기존 성공 job 자동 재실행은 수행하지 않았다.
- discovery callable은 `requestSeasonDiscovery`, `retrySeasonDiscovery`, `retrySeasonDiscoveryAfterExtractionFix`, `cancelSeasonDiscovery`, `resolveSeasonDiscoveryCandidate`다. enqueue trigger는 `onSeasonDiscoveryQueued`, watchdog은 `reconcileSeasonDiscoveryJobs`다.
- 환경 변수는 기존 Worker URL/service account/audience를 재사용하고, discovery queue/location만 `OUTPICK_LOOKBOOK_DISCOVERY_TASKS_QUEUE`, `OUTPICK_LOOKBOOK_DISCOVERY_TASKS_LOCATION`으로 분리한다.
- watchdog의 `collectionGroup("seasonDiscoveryJobs").where("status", "in", ...)`는 `firestore.indexes.json`의 `seasonDiscoveryJobs.status` ASCENDING/COLLECTION_GROUP field override가 필수다. Development에서 `READY` 확인 뒤 실제 stale job 재dispatch를 통과했으며 `functions/src/index.contract.test.ts`가 이 배포 계약을 고정한다.
- 시즌 목록·이미지 fix 재시도 callable은 각각 `retrySeasonDiscoveryAfterExtractionFix`, `retryLookbookExtractionAfterFix`다. 총 관리자 인증 뒤 job의 `fixed`, stage에 맞는 상위 `retryAvailableRuntimeVersion`, generation/snapshot을 서버에서 재검증한다.
- 기존 `requestSeasonDiscoveryImprovement`, `reanalyzeSeasonDiscoveryWithLatestExtractor`, 이미지 동일-version 재분석 export와 `status + improvementRequested` 인덱스 계약은 제거했다. 운영에 배포된 기존 callable 삭제와 인덱스 반영은 별도 승인 대상이다.
- Codex는 IAM private `lookbookExtractionIssueOpsRead`, `lookbookExtractionIssueOpsWrite`, `verifyLookbookExtractionFix`와 환경 필수 CLI로 allowlist evidence만 조회·변경한다. CLI는 고정 사용자 access token으로 환경별 exact operator service account의 IAM Credentials `generateIdToken`만 직접 호출하며 broad impersonation은 사용하지 않는다. compare-and-set과 audit을 적용한다.
- Worker IAM private `/runtime-contract`와 server-only `lookbookExtractionRuntime/current`를 도입한다. Production 100% traffic, runtime version과 실제 URL smoke를 확인한 verifier만 `fixed`와 정확한 영향 job의 `다시 가져오기 가능`을 기록한다.
- Phase 1 순수 계약은 Functions `functions/src/lookbook/import/extractionIssueContract.ts`, Worker `tools/lookbook-import-worker/src/extraction/issue-contract.ts`와 공유 golden vector `contracts/lookbook-extraction-issue-v1.json`에 있다. Phase 2는 `issue-policy.ts`, `issue-recorder.ts`, 이미지/시즌 processor에 자동 occurrence/cluster/job projection을 연결했다. 예상 수 미확인 단독 결과는 issue에서 제외하고, cluster에는 영향 domain/brand 표본을 저장하지 않는다. 배포 전 구형 Worker 요청이 fixed projection 뒤 늦게 완료돼도 cluster `blockedRuntimeVersion`은 내려가지 않으며, 늦은 job과 duplicate에는 검증된 `fixedRuntimeVersion`을 retry-ready로 투영한다. 이미 verified인 cluster의 후속 성공은 terminal cluster를 다시 전이하지 않고 해당 job projection만 닫는다.
- Phase 3 운영 API는 `functions/src/lookbook/issueOperations/`의 strict contract/auth/service/functions 경계와 `tools/lookbook-extraction-issue-ops/` CLI에 있다. 목록의 `brandID` filter와 최근 브랜드/job 사례는 제거했고 정확한 영향 job은 `extractionIssueFingerprint` collection-group projection으로 조회한다. Development와 Production에 전용 operator, read/write private Function, projection index와 audit TTL을 적용했고 실제 Cloud Run URI audience로 무인증 403·operator read·데이터 변경 없는 write 404 smoke를 통과했다.
- Phase 4는 Worker IAM 전용 `/runtime-contract`, `/smoke/extraction`과 Functions `verifyLookbookExtractionFix`, 10분 projection reconciler를 사용한다. verifier는 요청 environment와 runtime project/service를 fail closed하고 Cloud Run v2 observed traffic 100%, runtime/source revision, 대표 job 실제 재추출과 ground truth를 통과한 경우만 fixed/retry-ready를 기록한다. Development와 Production 모두 Worker Invoker와 해당 Worker service 한정 Viewer를 적용했다.
- Functions 재배포 뒤 private HTTP Function의 operator `roles/run.invoker`가 제거될 수 있으므로 배포 후 IAM smoke와 정확한 환경별 operator binding을 재확인한다. 2026-08-05 Development `verifyLookbookExtractionFix` 재배포에서는 `outpick-extraction-ops-dev` binding만 복원했고 공개 invoker는 추가하지 않았다.
- occurrence evidence는 7일, cluster 대표 evidence 한 개는 미해결 동안 보존하며 `verified/wontFix` 뒤 cluster와 함께 60일 보존한다. 상세 계약은 `docs/ai/tasks/lookbook-extraction-issue-operations/`를 따른다.

## Chat UGC safety/moderation v1 계약

- exact contract: `contracts/chat-moderation-v1.json`
- 장기 결정: ADR-024
- task: `docs/ai/tasks/chat-ugc-safety-room-moderation/`
- Phase 3.1 Functions는 `chat/moderation/{contracts,service,functions}.ts`의 `acknowledgeRoomClosure`를 추가하고, `chat/cleanup/moderationCleanup.ts`가 방 콘텐츠 즉시 정리와 14일 후 잔여 membership/tombstone 정리를 소유한다.
- `moderationRoomCleanupJobs` schema v2는 `cleanupPhase: content | retention`과 `status: awaitingExpiry`를 사용한다. 기존 `status + nextAttemptAt` index로 14일 due 작업을 조회하며, 완료 뒤 job 자체는 기존 7일 TTL을 사용한다.
- 종료 방은 `Rooms/{roomID}.tombstoneSchemaVersion = 1` 공용 문서로 최대 14일 남는다. Rules는 활성 계정이면서 본인 `joinedRooms/{roomID}` projection이 남은 경우의 단건 read만 허용하고, Messages/media 접근은 계속 거부한다. 기존 `roomClosureNotices` TTL은 legacy 자연 만료용으로 유지한다.
- Socket `roomClosureWatcher.js`는 cleanup job을 단일 listener로 관찰해 `room:closed` emit·registry 제거·socket leave를 수행한다. completed job도 관찰해 빠른 cleanup과의 경합에서 이벤트를 놓치지 않는다.
- 2026-08-11 접속 중 방장 종료 즉시 이벤트에 `closureType: closedByOwner`, `closureNoticeCode: ownerDeleted`를 추가했다. Production Socket build `a97273b4-46b5-4134-a82f-39a95e9b8eb0`, revision `outpick-socket-p31-owner-close-0811`, digest `sha256:29ddb169d993b5623fe3f7a9b8cf5bf2ac3ac2d508275a35604e7b47598ae379`가 traffic 100%이며 canonical readiness 정상·배포 직후 ERROR 0이다. 직전 `outpick-socket-account-cap-v2-0810`은 0% rollback으로 보존한다.
- 후속 재QA에서 handler 직접 emit과 cleanup watcher emit의 중복 가능성을 확인해 handler가 ACK만 반환하고 watcher가 종료 emit·registry 제거·socket leave를 단독 소유하도록 바꿨다. Socket 70/70 뒤 Production build `74f8b018-1b4c-46ea-97de-9a226518d257`, revision `outpick-socket-p31-close-dedupe-0811`, digest `sha256:7cb2082aea3755a9f7bb395551bfe499cf0dfbb787e590a530a15e7103738fda`를 readiness·ERROR 0 확인 후 traffic 100%로 전환했다. 직전 `outpick-socket-p31-owner-close-0811`은 0% rollback이다.
- Phase 3 Functions/Rules/Indexes/Storage/Socket의 Production 배포를 완료했다. 이후 폐쇄 방 read Rules와 최상위 `Rooms` query가 불일치해 앱 목록·검색·참여방 ID 조회·방 이름 중복 확인에 `isClosed == false`, `lifecycleStatus == active` 조건을 공통 적용했다. 배포 전 전체 원격 구성 감사에서 기존 원격 전용 index/field override가 0개임을 확인하고, 기존 검색 index 2개는 보존한 채 활성 검색 index 2개와 활성 목록 index 1개만 추가 배포했다. 신규 3개는 모두 `READY`이며 변경된 Production Kakao QA 앱의 오픈채팅 목록 진입에서 권한·index 오류가 없음을 확인했다.

### Server authority

- `moderationPrincipals/{moderationPrincipalID}`: 장기 제재 원장.
- `moderationPrincipalAliases/{aliasID}`: provider subject의 versioned HMAC alias. raw subject/email/token 저장 금지.
- `moderationAccounts/{uid}` schema v2: `accountStatus`와 moderation principal/status를 함께 가진 Rules·Functions·Socket·Storage용 현재 UID capability projection.
- `moderationUserReports`, `moderationRoomReports`, `moderationAuditLogs`: client direct read/write 금지, callable admin/user API만 사용.
- `moderationReportRateLimitBuckets`, `moderationAdminRateLimitBuckets`: server-only 분 단위 burst counter. detail·message snapshot·provider identity는 저장하지 않고 TTL 2일로 정리한다.
- `moderationCommentWriteRateLimitBuckets`: `functions/src/lookbook/comments/service.ts` transaction이 canonical principal 기준 댓글·답글 합산 UTC 분당 20회를 집계하는 server-only bucket이다. 본문·post/comment ID는 저장하지 않고 `expiresAt` TTL 2일을 사용한다. createComment/createReply는 UUID `clientRequestID`와 결정적 SHA-256 comment ID로 replay를 quota 소비 없이 멱등 처리한다.
- client Rules는 댓글 rate bucket read/write를 모두 거부하며 TTL field override는 `firestore.indexes.json`이 소유한다. 배포 대상은 Functions·Rules·Indexes로 분리하고 이 구현 단계에서는 배포하지 않는다.
- `Rooms/{roomID}/bans/{moderationPrincipalID}`: creator 전용 서버 mutation, client direct read/write 금지.
- `Rooms.lifecycleStatus=closedByModeration`: join/read/write/Socket/push 차단 source.
- `chatMessageCleanupJobs`, `moderationRoomCleanupJobs`: transaction 밖 Storage·projection 물리 정리의 deterministic retry source.
- `Rooms/{roomID}/MediaUploads/{uploadID}`: Phase 7 quarantine 기술 검증 상태 머신 후보. `uploading → queued → processing → ready | canceled | failed | expired`이며 ready 전에는 message/seq가 없다.
- Phase 7 상세 Functions·Cloud Tasks·Cloud Run Job·IAM·evidence 구현 순서는 `docs/ai/tasks/chat-ugc-safety-room-moderation/phase-7-implementation-plan.md`를 따른다.

### Phase 1 구현 Functions·Socket·Rules 경계

- `getMyModerationState`: `functions/src/moderation/functions.ts` → provider identity → versioned HMAC alias → principal/account transaction.
- HMAC current/previous key 조회 경계는 `functions/src/moderation/state.ts`, safe capability DTO는 `contracts.ts`가 소유한다.
- 기존 Auth 계정 dry-run/backfill은 `functions/scripts/backfill-moderation-principals.mjs`를 사용한다. `outpick-test`와 `outpick-664ae`만 허용하고 기본은 dry-run이며, unresolved가 1명이라도 있으면 `--apply`를 중단한다. Google·Apple은 단일 Firebase `providerData`, Kakao는 `kakao:{숫자 ID}` 후보와 `KAKAO_ADMIN_KEY`의 `/v2/user/me` 응답 ID가 정확히 일치할 때만 resolve한다.
- Production apply는 `--confirm-production APPLY_MODERATION_PRINCIPAL_BACKFILL_TO_OUTPICK_664AE`와 `--expected-total`, `--expected-google`, `--expected-kakao`를 모두 요구한다. expected total과 두 provider 합계, 실제 건수가 다르거나 canonical Secret 이름이 아니면 HMAC Secret 조회와 Firestore write 전에 중단한다. Admin Key·HMAC Secret은 gcloud stdout을 프로세스 메모리에서만 읽고 출력하지 않으며 summary는 provider·unresolved reason별 건수만 포함한다.
- `functions/src/shared/accountStatus.ts`는 `moderationAccounts` 한 문서에서 `accountStatus`와 moderation capability를 함께 판정한다. 계정 삭제 요청·취소와 principal binding은 `users.accountStatus` 원본과 projection을 같은 transaction에서 갱신한다.
- Socket `moderation/capabilities.js`와 auth/watch/handler는 단일 `moderationAccounts` 조회/listener로 deletionPending·restricted·suspended와 stateVersion 변경을 처리한다.
- Firestore·Storage Rules는 단일 projection 누락을 fail closed하고 restricted read와 active write를 분리한다. Storage media read는 account projection + active room, upload는 Socket이 capability/room access 확인 뒤 만든 `Rooms/{roomID}/MediaUploads/{messageID}` pending reservation + active room을 읽어 Rules의 Firestore 문서 조회 2개 제한 안에 머문다.
- iOS는 `getMyModerationState` 호출 뒤에만 사용자 문서와 앱 콘텐츠를 읽는다.
- `accountDeletion/cleanup.removePrivateState`는 삭제 완료 시 `moderationAccounts/{uid}`를 제거하고 principal·alias는 보존한다. 재가입 projection은 bootstrap callable이 다시 만든다.
- schema v2 운영 backfill은 `functions/scripts/backfill-account-capabilities.mjs`를 사용한다. 기본 dry-run이며 Production apply는 확인 문자열과 예상 사용자/ projection 건수 일치를 요구한다. 원격 Rules와 index/TTL 전체 구성 감사는 각각 `audit-firebase-rules.mjs`, `audit-firestore-indexes.mjs`를 사용한다.

### Phase 2 신고·관리자 처리 경계

- 일반 사용자 callable: `submitUserReport`, `submitRoomReport` → `functions/src/moderation/reports/`.
- 플랫폼 관리자 callable: `listModerationReports`, `getModerationReportDetail`, `mutateModerationReview`, `mutateAccountModeration` → `functions/src/moderation/admin/`.
- 모든 callable은 App Check와 account capability를 확인한다. 관리자 API는 active `platformAdmins/{uid}`를 추가 확인하고 계정 제재는 5분 이내 `auth_time`을 요구한다.
- 신고 transaction은 aggregate/submission/reporter/rate bucket을 원자적으로 갱신한다. 동일 submission을 먼저 확인하므로 retry는 quota를 소비하지 않는다.
- 관리자 mutation은 `caseVersion`/`stateVersion`, deterministic audit ID와 append-only audit으로 동시 처리와 재전송을 수렴시킨다.
- index/TTL: `firestore.indexes.json`; client deny: `firestore.rules`; transaction 회귀: `firestore-tests/moderation-reports.emulator.test.mjs`.
- 2026-08-10 Production 승인으로 Phase 2 index/rules와 exact Function 6개를 `outpick-664ae`에 배포했다. 기존 원격 index/TTL은 유지됐고 신규 신고 index 2개는 `READY`, Function 6개는 `ACTIVE`, 무인증 direct POST는 401이다. 별도 승인된 임시 Token Creator/App Check debug token 절차로 활성 Kakao 관리자의 목록 성공과 Google 비관리자의 `PERMISSION_DENIED`를 확인했다. smoke rate bucket은 원복했고 임시 debug token·IAM binding과 최근 ERROR 로그 잔존은 모두 0건이다.
- platform admin 최초 등록·회수는 `functions/scripts/manage-platform-admin.mjs`와 `docs/ai/runbooks/PLATFORM_ADMIN_OPERATIONS.md`를 사용한다. Production은 provider별 단일 계정, 전체 Auth 예상 건수와 exact confirmation이 모두 맞아야 쓰기 전에 gate를 통과한다.

### Phase 1 Development rollout — 2026-08-07

- project: `outpick-test`; Production `outpick-664ae` 미변경.
- Secret: `MODERATION_PRINCIPAL_HMAC_KEY_V1` version 1.
- backfill: Google 1명 resolved, unresolved 0; moderation account/principal/alias 각각 1개, raw subject·email·token 필드 0개.
- Functions: `getMyModerationState`와 capability 영향을 받는 기존 callable/scheduler 15개 배포.
- Firestore·Storage Rules: Development 배포 완료.
- Socket: revision `outpick-socket-development-00002-hal`, traffic 100%, canonical `/readyz` 정상, 배포 직후 ERROR 0건.
- 실제 Kakao QA: restricted·stateVersion 2 전환 → 앱 재인증 삭제 예약 → 승인된 단일 요청 grace 만료 → finalizer 1회 completed → Auth/users/moderationAccounts 제거와 alias/principal 보존 → 동일 Kakao 재연결 뒤 기존 principal의 restricted projection 복원까지 통과했다. 보존되는 moderation alias/principal의 raw email·subject·token·providerUserID 필드는 0개다.
- Kakao Auth custom-token의 요청 token claim은 bootstrap에 사용되지만 Firebase Admin `UserRecord.customClaims`에 영구 보관되지 않는다. Phase 1-P migration helper는 이 값을 영구 보강하지 않고 UID 후보를 Kakao Admin API로 재검증해 메모리에서만 binding 입력으로 사용한다. 실제 신규/재가입 binding 검증은 `getMyModerationState` 호출 뒤 `moderationAccounts`와 provider별 HMAC alias를 기준으로 한다.

### Phase 1-P Production readiness — 2026-08-07

- Auth 읽기 전용 dry-run: total 2/resolved 2/unresolved 0, Google 1/Kakao 1/Apple 0.
- `MODERATION_PRINCIPAL_HMAC_KEY_V1`: 원문 출력·로컬 저장 없이 생성, version 1 enabled.
- `getMyModerationState`: Production exact target 단일 배포, Node.js 24 Gen 2 ACTIVE, Secret version 1 binding. 무인증·App Check 없는 POST는 401 `UNAUTHENTICATED`, 배포 후 ERROR 0건.
- backfill: apply 직전 total 2/Google 1/Kakao 1/unresolved 0 재확인 뒤 exact gate로 처리. account/principal/alias 각각 2개, 모두 active, 참조 무결성 정상, 금지 필드·Auth 민감 원문 값 0개.
- capability 영향 Functions: profile 4/engagement 4/comment 3/safety 3/account deletion finalizer 1의 exact target 15개 배포. 15/15 Node.js 24 Gen 2 ACTIVE, ERROR 0, finalizer scheduler ENABLED, 이전 source generation 15개 보존.
- Firestore Rules: 배포 직전 Emulator Rules 35/35·transaction 11/11 통과. 새 ruleset `82942b4b-d110-4ab0-8f09-ab0b4e5aad62`와 로컬 SHA-256 일치, 이전 `bce94c07-bb86-4f9c-a74e-e14dc954085c` 보존.
- Storage Rules: 새 ruleset `599b1ae1-21b0-4be1-a2f6-aa576369221a`와 로컬 SHA-256 일치, 이전 `e0e75181-a23b-4dcf-a13c-df95bb9a70c6` 보존.
- Socket candidate: build `2719bc50-1c06-45d6-923a-1549ad2d7ffe`, revision `outpick-socket-moderation-p1p`, digest `sha256:403ecf364fbfa0ff3d040fed7d888b000a63539f485ea9c88387f3e949fe8ccd`, traffic 0%, Ready/readiness 200/ERROR 0. live `outpick-socket-00008-4wl` 100% 유지.
- Socket traffic blocker: candidate의 `socket.io-parser 4.2.6`이 high GHSA-2m8v-j782-fhvr에 해당한다. 4.2.7 lockfile patch·69/69·audit·새 candidate 전 traffic 전환 금지.
- Socket high patch: `package-lock.json`만 4.2.7로 갱신, check·69/69·production audit high 0/critical 0. 기존 4.2.6 candidate는 traffic 금지.
- Socket patched candidate: build `3c6db117-22f6-46a9-93fb-112f6a0f64ae`, revision `outpick-socket-moderation-p1p-r2`, digest `sha256:a7c0a095c64adf0b83459f16a0caf3f68378ce3fffdaea0e919555a1da3b7dc5`, traffic 0%, Ready/readiness 200/ERROR 0. live `outpick-socket-00008-4wl` 100% 유지.
- Production Socket runtime identity `outpick-socket@outpick-664ae.iam.gserviceaccount.com`은 revoked/disabled Firebase ID Token 확인용 project custom role `projects/outpick-664ae/roles/outpickSocketFirebaseAuthVerifier`를 사용한다. 포함 permission은 `firebaseauth.users.get` 하나다. 2026-08-07 기존 Google QA 계정으로 patched candidate Socket.IO 인증 handshake를 통과했고 테스트 Token Creator binding은 회수했다.
- 같은 runtime identity의 기존 predefined 역할은 `roles/datastore.user`, `roles/storage.objectAdmin`, `roles/firebasecloudmessaging.admin`이다. 실제 Socket 사용 범위는 Firestore document query/listener/transaction/write/delete, 방 Storage prefix list/delete, FCM message create이며 최소 권한 축소는 live와 분리한 candidate identity에서 검증 후 적용한다.
- Production 최소 권한 Socket runtime role은 `projects/outpick-664ae/roles/outpickSocketRuntime`이며 Auth `firebaseauth.users.get`, Firestore `datastore.databases.get`과 entity allocate/create/delete/get/list/update, Storage object list/delete, FCM message create 총 11개 permission을 포함한다. 새 identity `outpick-socket-runtime-v2@outpick-664ae.iam.gserviceaccount.com`에는 이 role 하나만 있다.
- 최소 권한 revision `outpick-socket-moderation-p1p-r3-lp`, tag `moderation-p1p-r3-lp-qa`는 patched r2와 같은 digest를 사용하며 Production traffic 100%, Ready/canonical readiness 200이다. 기존 Google QA 인증과 격리 Firestore read/write/delete·Storage list/delete·FCM fanout smoke를 통과했고 ERROR/잔존 QA 데이터는 0건이다.
- 새 live identity `outpick-socket-runtime-v2@...`와 rollback revision의 기존 `outpick-socket@...`은 모두 `outpickSocketRuntime` role 하나만 사용한다. 기존 identity의 broad Datastore User·Storage Object Admin·Firebase Cloud Messaging Admin와 구 Auth verifier binding은 제거했고 구 verifier role은 soft-delete했다.
- 2026-08-08 Production Simulator active smoke: Google·Kakao 모두 bootstrap과 메인 탭 기본 read를 통과했고 Kakao 세션의 브랜드 좋아요 `0→1→0`으로 write·원복을 확인했다. QA용 App Check debug token은 원문 비노출로 임시 등록하고 로그아웃 뒤 삭제했으며 기존 등록 1개만 남았다.

### Phase 2 이후 예정 Functions·Socket·Rules 경계

- Functions 신규 경계: `functions/src/moderation/{identity,capability,reports,admin,audit}/`와 chat delete/ban/succession service.
- Socket 경계: `Socket/src/auth`, `users/userLookup`, `rooms/roomAccess`, message/media handlers, `push/chatPushService`.
- Firestore Rules는 current UID의 `moderationAccounts`와 room ban/lifecycle을 읽고, safe action 외 UGC write를 capability matrix로 거부한다.
- Storage Rules는 quarantine owner의 exact reservation write만 허용하고 ready materialization은 서버만 수행한다.
- platform admin API는 `platformAdmins/{uid}`, App Check, expected version과 고위험 action의 5분 이내 `auth_time`을 검증한다.

### Index·retention

- 신고 queue: reviewState + priorityClass + slaDueAt + lastReportedAt.
- 제한 만료 정규화: moderationStatus + restrictedUntil.
- 미디어 cleanup: collection group MediaUploads의 processing/terminal 상태 + expiresAt, 실패한 로컬 outbox 7일 계약과 서버 quarantine cleanup을 분리한다.
- message/room cleanup: status + nextAttemptAt.
- Production TTL은 개인정보 보존 목적·기간 승인 전 활성화하지 않는다. Phase 7은 신고자가 선택한 attachment만 결정적 evidence bundle로 복사하고 처리 결과별 retention cleanup을 사용한다.

### 검증 진입점

- Functions identity/capability/report/idempotency/admin concurrency tests.
- Socket auth disconnect/room ban/block push/rate reconnect/media ready tests.
- `firestore-tests`의 moderation Firestore·Storage Rules emulator tests.
- 실제 provider 재연결과 전용 Cloud Run media 기술 검증·metadata 제거는 Development 수동 QA다.

### Phase 6 Production rollout — 2026-08-18

- Functions: `createComment`, `createReply` exact target이 asia-northeast3 Node.js 24 `ACTIVE`다. 배포 이후 ERROR 0을 확인했다.
- Firestore: `moderationCommentWriteRateLimitBuckets.expiresAt` TTL이 `ACTIVE`다. Rules는 server-only rate bucket의 client read/write deny를 포함해 Production에 release했으며 Storage Rules와 composite indexes는 변경하지 않았다.
- Socket: 최종 로그 최소화 보정 Cloud Build `de071fbc-21f9-4f9f-81d4-87e8d94ca292`, revision `outpick-socket-p6-log-min-0818`, digest `sha256:c558c3b383185a00d395c660344d33ea29d37de23a243fd401e4e0531405022c`가 traffic 100%다. canonical readiness 200과 ERROR 0을 확인했고 `outpick-socket-p6-text-rate-0818`은 0% rollback으로 유지한다.

### Phase 5 Production rollout — 2026-08-12

- Firestore: room ban 목록, succession due-job, owner active-room composite index 3개가 `READY`이고 succession job TTL이 `ACTIVE`다. 개인정보 보존 기간 승인 전 `bans.expiresAt` TTL은 활성화하지 않았다.
- Functions: 기존 Phase 5 대상 7개와 비참여 화면 서버 권위 상태 조회 `getMyRoomAccess`까지 8개가 asia-northeast3 Node.js 24 `ACTIVE`다. `getMyRoomAccess`는 인증 UID로 member와 canonical principal ban을 확인하고 `member | joinable | banned | closed`만 반환한다. retry scheduler는 5분·Asia/Seoul `ENABLED`다.
- Socket: Cloud Build `21bc669c-10e5-4f5e-85fd-b44e34b11bf6`, revision `outpick-socket-p5-ban-0812`, digest `sha256:3ed111783e176674719d11f17e0aec0298e41b562208099b46b0bb4512f49868`가 traffic 100%다. canonical readiness와 배포 직후 ERROR 0을 확인했고 `outpick-socket-p4-block-0811`은 0% rollback으로 유지한다.
- Production 데이터 감사는 closed Rooms 11, active room 0, bans 0, succession jobs 0이었다. 기존 방은 모두 `isClosed`·lifecycle 필드를 가져 backfill/migration이 필요하지 않았다.
- 신규 callable 3개는 올바른 무인증 envelope에서 HTTP 401을 반환했다. succession scheduler는 빈 queue에서 수동 1회 성공했고 이후 Functions·Socket·Scheduler ERROR와 ban/job 잔존은 0건이다. 최초 잘못된 envelope 3건의 `Invalid request` 로그는 검증 입력 오류로 구분해 기록했다.
