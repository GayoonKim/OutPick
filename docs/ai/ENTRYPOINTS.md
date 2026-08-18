# OutPick Entrypoints

## 목적

기능 수정이나 새 기능 추가 시 AI 에이전트가 어디부터 봐야 하는지 빠르게 확인하기 위한 인덱스 문서다.

루트 문서는 공통 진입점과 세부 문서 링크만 유지한다. 기능별 상세 진입점은 필요한 문서만 추가로 읽는다.

## 공통 진입점

- 앱 시작/루트 라우팅: `OutPick/App/AppCoordinator.swift`
- iOS Development/Production 빌드 환경: `Configurations/` → `OutPick.xcodeproj/xcshareddata/xcschemes/` → `scripts/build/validate-and-copy-firebase-config.sh` → `OutPick/Info.plist`
- Scene 연결/초기 DI와 bootstrap 실패 복구: `OutPick/App/SceneDelegate.swift`, `OutPick/App/Bootstrap/`
- 탭 조립: `OutPick/App/TabBarController/Composition`
- 기능 코드: `OutPick/Features`
- 공통 인프라: `OutPick/Infra`
- iOS Cloud Functions 공통 transport: `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift`
- iOS Cloud Functions 기능 adapter: `OutPick/Features/*`의 `CloudFunctions*Repository/Client`와 Lookbook `CloudFunctionsMappers/`
- iOS local database bootstrap/Store: `OutPick/DB/GRDB/Core/AppDatabase.swift`, `OutPick/DB/GRDB/Stores/` (`AppDatabase.live()`는 `throws`)
- Chat persistence 계약/조립: `OutPick/Features/Chat/Persistence/`
- Firestore 문서 ID 경계: `docs/ai/tasks/firestore-document-id-boundary-cleanup/`, ADR-020
- 공통 키보드 dismiss helper: `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`
- 로컬 DB/데이터 schema: `docs/ai/entrypoints/DATA.md`
- Firebase Functions flat export: `functions/src/index.ts`
- Firebase Functions 공통 runtime/callable: `functions/src/core/`
- Firebase Functions 기능 구현: `functions/src/{auth,brand,chat,lookbook,moderation,profile,styleMoods}/`
- Kakao custom-token 함수·전용 runtime identity: `functions/src/auth/{functions,kakaoService,runtime}.ts`
- 계정·공개 프로필 서버 경계: `functions/src/profile/`, `functions/src/shared/accountStatus.ts`
- 계정 삭제 서버 상태 머신·정리 worker: `functions/src/accountDeletion/` → `firestore.rules`/`storage.rules`/`firestore.indexes.json`
- 계정 capability·삭제 차단: `functions/src/shared/accountStatus.ts`/`functions/src/accountDeletion/repository.ts` → `moderationAccounts/{uid}` schema v2 → `firestore.rules`/`storage.rules`와 `Socket/src/auth/socketAuthMiddleware.js`/`Socket/src/handlers/connectionHandlers.js`
- 스타일 무드 서버·seed·할당: `functions/src/styleMoods/`, `functions/src/shared/styleMoodAssignmentPolicy.ts`, `functions/src/lookbook/admin/seasonMoodFunctions.ts`, `functions/seeds/style-moods.v1.json`
- 브랜드·채팅 개발 데이터 선택 초기화: `functions/src/developmentReset/brandChatManifest.ts` → `functions/scripts/audit-brand-chat-reset.mjs` → 승인 후 `functions/scripts/reset-brand-chat-data.mjs`
- iOS 스타일 키워드 관리자·검색: `LookbookAdminHomeView.swift` → `LookbookCoordinator.pushStyleMoodManagement()` → `StyleMoodManagementViewModel.swift` / `StyleMoodManagementView.swift`
- iOS 브랜드·시즌 스타일 검색/선택: `AdminBrandManagementViewModel.swift` / `AdminBrandManagementView.swift` → `SeasonMoodManagementView.swift` / `StyleMoodSelectionSection.swift`
- iOS 브랜드 search-first picker 정책: `StyleMood.swift`의 `StyleMoodPickerPolicy` → `StyleMoodSelectionSection.swift` → `CreateBrandView.swift` / `AdminBrandManagementView.swift`
- Phase 5.1 스타일 관리 UX 구현·QA: `StyleMoodEditorView.swift` / `StyleMoodSelectionSection.swift` / `SeasonMoodManagementView.swift` → `docs/ai/tasks/style-mood-personalization-account-privacy/plan.md`의 Phase 5.1 → `decisions.md` D62~D64 → `qa-checklist.md`
- iOS 계정 bootstrap·새 온보딩: `AppCoordinator.swift` → `LoadCurrentUserBootstrapUseCase.swift` → `ProfileCoordinator.swift` → `ProfileSetupViewController.swift` → `StyleMoodOnboardingViewController.swift`
- iOS 계정/공개 프로필 read·mutation: `FirestoreCurrentUserAccountRepository.swift`, `FirestoreUserPublicProfileRepository.swift`, `CloudFunctionsProfileMutationRepository.swift`
- iOS 마이페이지 프로필·관심 스타일 편집: `MyPageCompositionRoot.swift` → `MyPageCoordinator.swift` → `ProfileEditViewController.swift` / `StylePreferenceEditViewController.swift` → `UpdatePublicProfileUseCase.swift` / `UpdateStylePreferencesUseCase.swift`
- iOS 일반 사용자 브랜드 요청·내역: `LookbookHomeView.swift` 검색 빈 결과 → `BrandRequestView.swift` → 제출 후 `MyBrandRequestsView.swift`; 재진입은 `MyPageViewController.swift`의 `ACTIVITY` → `MyPageCoordinator.swift` → `DefaultAppContentRouter.openMyBrandRequests()`
- iOS 계정 삭제·취소·로컬 scrub: `MyPageCoordinator.swift` → `AccountDeletionConfirmationViewController.swift` / `AccountDeletionPendingViewController.swift` → `RequestAccountDeletionUseCase.swift` / `CancelAccountDeletionUseCase.swift` → `AccountDeletionReceiptStore.swift` / `AccountDeletionLocalDataScrubber.swift` → `AppCoordinator.swift`
- iOS 환경/Firebase bootstrap: `AppRuntimeConfiguration.swift` → `AppDelegate.configureFirebaseApp(runtimeConfiguration:)` → `OutPickAppCheckProviderFactory.swift` → Debug 구성·Simulator Debug Provider / Release 실기기 App Attest → `OutPick.Debug.entitlements` / `OutPick.entitlements`
- 계정 삭제 provider 재인증: `DefaultSocialAuthRepository.swift` → Google pending sign-in/동일 세션 reauthenticate 또는 Kakao 강제 login prompt → callable
- iOS 관심 스타일 브랜드 홈·전체 보기: `CurrentUserStylePreferenceStore.swift` → `LoadInterestedStyleBrandsUseCase.swift` → `LookbookHomeViewModel.swift` / `InterestedStyleBrandListViewModel.swift` → `LookbookCoordinator.swift`
- iOS 좋아요 에디토리얼 화면·독립 섹션 상태: `LikedView.swift` → `LikedBrandCardView.swift` / `LikedSeasonCardView.swift` / `LikedPostCardView.swift` → `LikedViewModel.swift` → `LookbookCoordinator.swift`
- iOS 브랜드 생성·로고 업로드 재시도: `CreateBrandView.swift` → `CreateBrandViewModel.saveBrand()` → `CloudFunctionsBrandStore.createBrand/updateLogoPaths` + `LookbookStorageService` → `CreateBrandFlowView`
- Lookbook import extraction core/evidence/version: `tools/lookbook-import-worker/src/extraction/`, `processor.ts`, `season-discovery.ts`
- 시즌 목록 durable discovery: `functions/src/lookbook/import/seasonDiscoveryJobs.ts` → `tools/lookbook-import-worker/src/season-discovery-processor.ts` → `brands/{brandID}/seasonDiscoveryJobs/{jobID}`. 생성 흐름 상태 owner는 `CreateBrandDiscoveryViewModel.swift`이며 infrastructure 오류 원문은 내부 로그로만 남기고 브랜드 등록 화면에는 안정된 사용자 문구를 전달한다. 관리자 issue projection/fixed 재시도 상태 owner는 `SeasonImportManagementViewModel.swift`와 `SeasonCandidateDiscoveryResult.extractionIssueUserState`다.
- 시즌 대표 이미지 보강 Phase 7: `tools/lookbook-import-worker/src/extraction/{image-candidates,season-cover}.ts` → `season-discovery.ts` → `season-discovery-processor.ts`. 상세 계약은 `docs/ai/tasks/lookbook-extraction-issue-operations/phase-7-season-cover-enrichment.md`이며 기존 iOS nullable `coverImageURL` 표시 계약은 유지한다.
- Lookbook import worker HTTP/OIDC 경계와 배포 계약: `tools/lookbook-import-worker/src/server.ts`, `config.ts`, `oidc-auth.ts` → `scripts/ai/deploy-lookbook-import-worker.sh` → `docs/ai/runbooks/LOOKBOOK_IMPORT_WORKER_DEPLOYMENT.md`
- Lookbook extraction adapter registry: `tools/lookbook-import-worker/src/extraction/adapters/{registry,cafe24,types}.ts`
- Lookbook extraction review/trust/resume: worker `src/extraction/review.ts`, Functions `src/lookbook/import/{functions,reviewContract}.ts`, iOS `LookbookExtractionReview*`
- Lookbook extraction count-based review gate/UI: worker `src/extraction/{quality,review}.ts`, iOS `LookbookExtractionReview.swift`, `LookbookExtractionReviewViewModel.swift`, `LookbookExtractionReviewView.swift`
- Lookbook expected-count 활성 gallery scope: worker `src/extraction/expected-count.ts`, YOUTH incident fixture/test
- Lookbook 시즌 상세 pagination·이미지 prefetch: `LoadSeasonDetailUseCase.swift`, `SeasonDetailViewModel.swift`, `SeasonDetailView.swift`, 공용 `BrandImageCache`→`ImageCachePipeline`
- Lookbook extraction evidence/issue 자동 기록(Phase 2 완료): worker `src/extraction/{retained-evidence,issue-policy,issue-recorder}.ts`, `processor.ts`, `season-discovery-processor.ts` → Functions `src/lookbook/import/evidenceCleanup.ts`. 배포 경합의 구형 occurrence 지연 도착은 `issue-recorder.ts`가 cluster blocked runtime을 단조 증가시키고 fixed/verified runtime의 job 재시도 projection을 복원한다.
- Lookbook extraction issue 공통 계약: `contracts/lookbook-extraction-issue-v1.json` → Functions `extractionIssueContract.ts` → Worker `extraction/issue-contract.ts` → `docs/ai/tasks/lookbook-extraction-issue-operations/`
- Lookbook extraction issue 내부 운영: Functions `src/lookbook/issueOperations/{contract,auth,service,functions}.ts` → CLI `tools/lookbook-extraction-issue-ops/src/{config,gcloud,index}.js`의 exact operator IAM Credentials `generateIdToken` → `docs/ai/runbooks/LOOKBOOK_EXTRACTION_ISSUE_OPERATIONS.md`
- Lookbook extraction fix 검증: Worker `src/{runtime-contract,server,processor}.ts`의 `/runtime-contract`, `/smoke/extraction` → Functions `src/lookbook/issueOperations/{releaseContract,releaseExternal,releaseService,releaseFunctions}.ts` → CLI `verify-fix`
- Lookbook extraction fixed-only iOS 재시도: `SeasonCandidateDiscoveryResult.swift` / `SeasonImportJob.swift` / `LookbookExtractionReview.swift` → 각 Cloud Functions Repository → `SeasonImportManagementViewModel.swift` / `LookbookExtractionReviewViewModel.swift` → 관리자 두 화면. 서버 entrypoint는 `retrySeasonDiscoveryAfterExtractionFix`, `retryLookbookExtractionAfterFix`다.
- Lookbook existing-season reconcile: worker `src/extraction/reconcile.ts`, Functions `src/lookbook/import/{functions,repairContract}.ts`, iOS `LookbookSeasonRepair*`
- Lookbook 관리자 remote preview 이미지: `Services/ImageLoading/LookbookRemotePreviewImage{Loading,Loader}.swift`, `Views/Shared/LookbookRemotePreviewImageView.swift`
- Lookbook extraction fixture/differential gate: `tools/lookbook-import-worker/src/fixture/`, `tools/lookbook-import-worker/fixtures/`, `npm run test:fixtures`
- Lookbook Cafe24 underscore-detail discovery 회귀: `tools/lookbook-import-worker/src/season-discovery.ts`, `fixtures/discovery/platform/cafe24-underscore-detail-list/`
- Socket bootstrap/application: `Socket/index.js`, `Socket/src/app/`
- Socket 기능 경계: `Socket/src/{auth,handlers,rooms,messages,media,lifecycle,runtime}/`
- Socket message idempotency 공통 경계: `Socket/src/messages/messageDeliverySingleFlight.js`, `Socket/src/messages/sequenceStore.js`
- iOS Socket 단일 ingress/admission/routing/reconnect: `OutPick/Infra/Realtime/RealtimeSocketListenerBinder.swift`의 `RealtimeSocketMessageIngressQueue`, `OutPick/Infra/Realtime/RealtimeSocketService.swift`의 `RealtimeSocketAdmissionState`·`RealtimeRoomRoutingState`·`RealtimeRoomJoinState`·Socket generation·visible strict suspend/rejoin, `OutPick/Infra/Realtime/RealtimeChatIngressOrdering.swift`, `OutPickTests/RealtimeSocketListenerBinderTests.swift`, `OutPickTests/RealtimeChatIngressOrderingTests.swift`
- iOS Chat route·비동기 진입 경쟁·edge-pop/방 생성 차단 정책: `OutPick/Features/Chat/ChatNavigationController.swift`, `OutPick/Features/Chat/ChatNavigationStackPolicy.swift`, `OutPick/Features/Chat/ChatOpenRoomRequestState.swift`, `OutPick/Features/Chat/ChatOpenRoomRequestRegistry.swift`, `OutPick/Features/Chat/ChatRoomRouteLifecycleState.swift`, `OutPick/Features/Chat/Controllers/{ChatViewController,RoomCreateViewController}.swift`, `OutPick/Features/Chat/ChatCoordinator.swift`, `OutPickTests/{ChatNavigationControllerTests,ChatNavigationStackPolicyTests,ChatOpenRoomRequestStateTests,ChatOpenRoomRequestRegistryTests,ChatRoomRouteLifecycleStateTests}.swift`
- iOS Chat background tap·message/announcement long press·cell action gesture 책임: `OutPick/Features/Chat/Controllers/{ChatViewController,ChatViewControllerExtension}.swift`, `OutPick/Features/Chat/Views/Cell/ChatMessageCell.swift`
- iOS Profile modal edge-swipe dismiss: `OutPick/Features/Profile/Views/UserProfileDetailViewController.swift`, `OutPick/Features/Profile/UserProfileDetailCoordinator.swift`, `OutPick/Infra/Utility/Transitions/ChatModalTransitionManager.swift`
- iOS visible Chat strict ordering/recovery: `OutPick/Infra/Realtime/RealtimeChatIngressOrdering.swift`, `OutPick/Infra/Realtime/FirebaseChatRealtimeGapRecoveryLoader.swift`, `OutPickTests/RealtimeChatIngressOrderingTests.swift`
- iOS lightweight Banner presentation/retry: `OutPick/Infra/Banner/BannerManager.swift`의 `RealtimeBackgroundRoomSessionOpening`·`BannerSubscriptionRetryPolicy`, `BannerPresentationQueueState.swift`, `OutPickTests/BannerPresentationQueueStateTests.swift`
- iOS 방별 fan-out 최종 dedupe: `OutPick/Infra/Realtime/RealtimeSocketService.swift`의 `ChatRoomSessionActor`, `OutPickTests/ChatRoomSessionActorTests.swift`
- 현재 Socket ingress 순서 보장 task: `docs/ai/tasks/socket-ingress-ordering-hardening/`
- iOS Socket candidate QA: `RealtimeSocketService.swift`의 DEBUG 전용 `SocketDebugQAConfiguration`, `OutPickTests/SocketDebugQAConfigurationTests.swift`
- iOS 발신 ACK 수렴: `ChatMessageSendReceipt.swift`, `ChatViewController.reconcileServerConfirmedOutgoingMessage`, `LookbookChatShareViewModel`의 동일 ID retry
- Socket room summary 단일 소유권: `Socket/src/messages/sequenceStore.js`가 seq transaction 안에서 `Rooms.lastMessage*`를 갱신하며, iOS `RealtimeSocketService`의 ACK 경로는 room summary를 직접 쓰지 않는다.
- Socket 자동 검증: `Socket/test/`, `Socket/scripts/run-tests.mjs`
- Phase 6 텍스트 전송 보호: Socket `src/utils/rateLimit.js`와 text/Lookbook/media handler가 canonical moderation principal·room·kind별 2초 bucket을 공유하고, Functions `src/lookbook/comments/{contracts,service,functions}.ts`가 댓글·답글 합산 분당 20회 Firestore transaction quota와 UUID 멱등 문서 ID를 소유한다. iOS 입력 상한/재시도 ID는 `ChatRoomMessageUseCase.swift`, `ChatUIView.swift`, `Create{PostComment,CommentReply}UseCase.swift`, 댓글 ViewModel/InputBar가 담당한다.
- Phase 6 메시지 개인정보 최소화: 신규 메시지의 `senderEmail`은 Socket/FCM/iOS `ChatMessage`/GRDB에서 제외하며 `GRDBMigrationRegistry.removeSenderEmailFromChatMessage`가 기존 로컬 column을 제거한다.
- Chat UGC safety/moderation v1 계약: `contracts/chat-moderation-v1.json` → ADR-024 → `docs/ai/tasks/chat-ugc-safety-room-moderation/{decisions,plan,progress,qa-checklist}.md`
- Chat moderation Phase 1 구현·Development rollout: iOS `CloudFunctionsCurrentUserModerationRepository`/`LoadCurrentUserBootstrapUseCase`/`AppCoordinator`/`ModerationNoticeViewController`, Functions `src/moderation/`와 `scripts/backfill-moderation-principals.mjs`, Socket `src/moderation/capabilities.js`, `firestore.rules`/`storage.rules` → 상세 `entrypoints/APP.md`, `entrypoints/CHAT.md`, `entrypoints/FIREBASE.md`, `entrypoints/TESTS.md`
- Chat moderation Phase 2 신고·관리자 API: iOS `ChatModerationReport.swift` → `ChatModerationReportingRepository.swift` → `SubmitChatModerationReportUseCase.swift`; Functions `src/moderation/{reports,admin,audit}/`; Rules/index/transaction QA `firestore.rules`, `firestore.indexes.json`, `firestore-tests/moderation-{capabilities.rules,reports.emulator}.test.mjs`
- Chat moderation Phase 3 삭제·Phase 3.1 공용 종료 tombstone: iOS `FirebaseChatRoomRepository.fetchJoinedRoomList`/`ChatModerationLifecycleRepository.swift` → `ChatRoomClosureAcknowledgementUseCase`/`JoinedRoomsViewModel`/`ChatCoordinator.handleRoomClosure`; 실시간·오프라인 확인 직후 목록 제거와 같은 세션 stale fetch 차단은 `ChatRoomClosureListUpdating`, `JoinedRoomsViewModel.removeRoomAfterRealtimeClosure`/`acknowledgeClosedRoom`; Functions `src/chat/{moderation,cleanup}/`의 `acknowledgeRoomClosure`와 `content → retention` cleanup; Socket `roomClosureWatcher.js`; Rules/transaction QA `firestore-tests/{moderation-capabilities.rules,chat-moderation.emulator}.test.mjs`
- Chat moderation Phase 4 전역 차단: `OutPick/Features/Moderation/{UserBlockVisibilityStore,UserBlockSnapshotStore,UserBlockSessionController}.swift` → `AppCompositionRoot`/`AppCoordinator` bootstrap → Chat·Lookbook·Profile·MyPage 공용 UseCase/Store; Functions `src/lookbook/safety/{blockContracts,functions}.ts`의 `blockUser`/`unblockUser`; Socket `src/push/chatPushService.js`의 수신자별 차단 push 억제 → 상세 `entrypoints/{APP,CHAT,FIREBASE,TESTS}.md`
- Chat moderation Phase 5 room ban UX 보정: `ChatMessageActionPolicy`/`ChatViewController`의 방장 메시지 `내보내기`, `ChatRoomSettingViewController`의 방장 전용 `차단 사용자` 버튼 → `ChatRoomBannedUsersViewController` 독립 관리 화면, 참여자 프로필·별도 관리 버튼, `ChatModerationLifecycleRepository.fetchMyRoomAccess` → Functions `getMyRoomAccess`의 서버 권위 `member | joinable | banned | closed` 판정.
- Chat account capability v2·Storage reservation 보정: `functions/scripts/backfill-account-capabilities.mjs`, `functions/scripts/audit-{firebase-rules,firestore-indexes}.mjs`; Rules 회귀 `firestore-tests/chat-media-storage.rules.test.mjs`
- Platform admin 운영: `functions/scripts/manage-platform-admin.mjs` → `functions/src/moderation/admin/platformAdminOperations.ts` → `docs/ai/runbooks/PLATFORM_ADMIN_OPERATIONS.md`
- Phase 6 통합 회귀/배포 gate: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-integration-tests.md`, `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-deployment.md`
- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`
- Firebase/Storage 운영 권한 확인: `docs/ai/entrypoints/FIREBASE.md`
- 단위 테스트: `OutPickTests`
- UI 테스트: `OutPickUITests`

## 세부 진입점

- 앱 조립, 탭, 주요 Feature: `docs/ai/entrypoints/APP.md`
- Chat 앱 화면/검색/채팅방 흐름: `docs/ai/entrypoints/CHAT.md`
- Lookbook 앱 화면/도메인: `docs/ai/entrypoints/LOOKBOOK.md`
- Profile 생성/수정/상세: `docs/ai/entrypoints/PROFILE.md`
- Data/GRDB/Repository boundary: `docs/ai/entrypoints/DATA.md`
- Firebase Functions/Firestore: `docs/ai/entrypoints/FIREBASE.md`
- 테스트: `docs/ai/entrypoints/TESTS.md`

## 작업별 진입점

| 포인터 | 문서 |
| --- | --- |
| 현재 작업과 최근 완료 상태 | `docs/ai/tasks/active.md` |
| 세션 복원 | `HANDOFF.md` |
| 장기 결정 | `docs/ai/ADR.md` |
| 데이터 계약 | `docs/ai/DATA_SCHEMA.md` |

최근 작업은 `active.md`에서 관련 task의 `decisions.md`와 `progress.md`로 들어간다. phase 전체 이력은 루트 인덱스에 복사하지 않는다.

## 변경 목적별 빠른 경로

| 변경 목적 | 읽기 순서 |
| --- | --- |
| 핵심 인프라 모듈화 | `tasks/core-infrastructure-modularization/design.md` → `contracts/README.md` → `active.md`가 가리키는 현재 phase 결정/계획/테스트 → decisions/plan/progress → ADR-019 → 네 현재 대형 진입점 |
| 삭제 purge queue/장애 | task decisions/progress → ADR-018 → `lookbook/deletion/purgeDrain.ts` → `lookbook/deletion/functions.ts` scheduler/query → `purgeLease.ts` → test |
| 삭제 요청 앱 목록/retry | task progress → `LOOKBOOK.md` 삭제 관리 → `FIREBASE.md` 삭제 lifecycle → iOS/Functions 구현 |
| 룩북 import/진단 | task progress → `architecture/LOOKBOOK_IMPORT_WORKER.md` → `FIREBASE.md` URL import → worker/앱 구현 |
| 브랜드 요청/관리 | `LOOKBOOK.md` 관리자 흐름 → `FIREBASE.md` 권한·요청 → 관련 task progress |
| 관심 스타일 브랜드 | 현재 task Phase 6 decisions/data contract → `LOOKBOOK.md` 관심 스타일 브랜드 → `FirestoreBrandRepository.swift` → 관련 ViewModel/View/테스트 |
| 계정 삭제 iOS | 현재 task Phase 8 decisions/plan → `PROFILE.md` 계정 삭제 iOS 흐름 → MyPage 화면/UseCase/Repository → `AppCoordinator.swift` → `TESTS.md` Phase 8 |
| 스타일 무드/seed | 현재 task decisions/seed spec → `DATA_SCHEMA.md` 스타일 무드 계약 → `functions/src/styleMoods/` → `firestore.rules`/indexes → rules test |
| 새 사용자 온보딩/프로필 | 현재 task progress → `PROFILE.md` → `AppCoordinator.swift` → Profile UseCase/Repository → Functions profile module/rules |
| Chat membership/cache | `CHAT.md` → `DATA_SCHEMA.md` Chat 계약 → 관련 task decisions/progress |
| Chat 신고·차단·삭제·room ban·계정 제재·게시 전 필터 | `tasks/chat-ugc-safety-room-moderation/decisions.md` → `contracts/chat-moderation-v1.json` → ADR-024 → `CHAT.md`/`FIREBASE.md`/`TESTS.md` → task plan/progress/QA |
| Chat route/lifecycle/gesture 완료 변경 | `CHAT.md`의 `Route/lifecycle/gesture 변경 파일 빠른 지도` → `tasks/chat-route-lifecycle-hardening/progress.md` → `TESTS.md`의 Chat route lifecycle hardening tests → task QA checklist |
| Firestore 문서 identity | ADR-020 → `DATA_SCHEMA.md` → `CHAT.md`/`LOOKBOOK.md` 문서 ID 경계 → `DATA.md` Repository boundary → `FIREBASE.md` rules → `TESTS.md` 경계 테스트 → task progress/QA |
| Chat 대규모 unread/read frontier | `tasks/active.md` → `tasks/socket-ingress-ordering-hardening/phase-6-unread-catch-up-read-frontier.md` → `CHAT.md` read frontier/realtime-only 3초 preview·즉시 persistence 및 진단 계측 진입점 → `TESTS.md` Phase 6-A~C 회귀·Phase 6-D QA |

작업 시작 시 이 문서와 `docs/ai/tasks/active.md`만 먼저 읽고, 표가 가리키는 세부 문서만 추가로 확인한다.
