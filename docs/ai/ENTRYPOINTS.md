# OutPick Entrypoints

- 공용 이미지 확대 화면: `Infra/Media/ImageViewer/ImageViewerChromeView.swift`(왼쪽 상단 닫기·하단 저장/번호/신고) → `SimpleImageViewerVC.swift`(제스처·페이지별 요청 식별/실패 재시도·저장 중복 방지). 채팅/갤러리/룩북/프로필 공용, 생성자·loader·저장 주입 계약 유지. [구현 계획·검증](tasks/shared-image-viewer-editorial/implementation-plan.md).

- 사진300MB·실패 사진 복구: `ChatPhotoSizePolicy` → `ChatImageTransportSourceNormalizer`/`ChatMediaSelectionChunker` → `ChatMediaSelectionUseCase.failedImages`/`preserveFailedImages` → `ChatViewController+MediaSelection` 기존 선택 원장 복원·재시도·삭제. 서버 `Socket/src/media/directMediaUploadService.js`. [계약·구현·검증](tasks/chat-media-preview-continuity/photo-size-failure-recovery.md).

- 원본 확보 지연 계측(2026-09-11): `ChatMediaSelectionUseCase`의 사진별 slot 대기 → `ChatMediaSourceAcquisition`의 provider 대기/파일 복사 → VC의 취소 사유. [분석 방법·재현 상태](tasks/chat-media-preview-continuity/acquisition-diagnosis.md).

- 미디어 버블 이미지 깜빡임 개선: `ChatMessageCell` → `ChatImagePreviewItem.stableID` → `ChatImagePreviewCollectionView`의 ID snapshot/최신 payload 분리 → `ChatImagePreviewCell`의 동일 첨부 이미지·로딩 유지. [구현·검증 기록](tasks/chat-media-preview-continuity/implementation.md), 상세 CHAT/TESTS 진입점 참조. 직접 업로드는 Development 배포/3장·70장 전송 확인 완료, Production 미배포다.

- 실제 직접 업로드 QA의 동시 초기화 회귀: `ChatMediaForegroundUploadService.swift`에서 URLSession 최초 접근/작업 생성을 stateQueue로 직렬화한다. `ChatMediaForegroundUploaderTests.swift`가 URLProtocol fake로 동시 첫 업로드 30개의 완료를 검증한다.

- 최신 직접 업로드 구현(미배포): `ChatImageTransportSourceNormalizer`/`ChatGIFMetadataStripper` → 파일 기반 `ProcessedImage`/`PreparedVideo` → `ChatMediaUploadUseCase` 첨부당 display/thumbnail → `RealtimeSocketService` 계약3 → `Socket/src/media/directMediaUploadService.js` 최종 경로 signed PUT·metadata 확인·메시지 원자 확정. `functions/src/chat/media/directUploadCleanup.ts` 취소/만료 정리. 상세 구현·QA는 CHAT와 `tasks/chat-media-bounded-parallel-upload/direct-upload-detailed-design.md` 참조.

- 최신 순차 묶음 전송: CHAT의 「최신: 묶음 순차 전송」. `ChatViewController+MediaSelection` 최종버블 선표시 → Container FIFO1 → UploadUseCase 묶음내 PUT4 → VC 메시지 UI 반영/실패후 반환. `ChatMediaBatchProgress` 합산진행률, PendingStore/Cell/ProgressView 고정원형+장수. [승인 설계](tasks/chat-media-bounded-parallel-upload/design.md).

- 원본 확보 중복콜백 크래시: `ChatMediaSourceAcquisition.swift` 최초callback gate, `OutPickTests/ChatMediaSourceAcquisitionTests.swift` 오류→취소/중복성공/동시콜백 회귀. CHAT 진입점과 서버pipeline QA 보고서 최신항목 참조.

- 사진 선택 후 버블 없음 진단: CHAT의 원본 확보 DEBUG 항목. `ChatViewController+MediaSelection.swift` → `ChatMediaSelectionUseCase.swift` → `ChatMediaSourceAcquisition.swift`에서 대기열/원장/파일 provider/복사 단계와 오류 domain·code만 기록한다.

- 정상 이미지 처리 후30초재시도 제거: FIREBASE의 dispatcher 완료 barrier 항목. `functions/src/chat/media/{functions,orchestrationService,readyService}.ts`가 worker 완료→ready/slot반환→Task응답 순서를 연결한다. 상세 QA/설계는 `tasks/chat-media-bounded-parallel-upload/qa/server-pipeline-optimization.md`.

- 미디어 finalize 통합·서버 제한 병렬: `tasks/chat-media-bounded-parallel-upload/qa/server-pipeline-optimization.md`. 앱 복구 계약은 CHAT, Socket/worker 설정·측정은 FIREBASE, 자동 회귀는 TESTS 진입점 참조. 실측 최적값 미확정.

- 미디어 전송 진행 표시: `OutPick/Features/Chat/Views/ChatMediaUploadProgressView.swift` → `ChatMessageCell.applyMediaUploadRecoveryState` → `ChatViewController.pendingRecoveryState`/`updateVisibleRecoveryIfPossible`. 원본 확보 후 사진 덮개·원형 진행, 서버 확인 중 회전, 성공 제거, 실패 회전 제거/기존 복구 버튼. 상태·재사용·렌더링 테스트 `OutPickTests/ChatMediaUploadProgressViewTests.swift`.

- 실제 미디어 전송 QA·방 내부 사진 보기 취소 결함: `docs/ai/tasks/chat-media-bounded-parallel-upload/qa/iphone14-live-transmission.md` → `ChatViewController.viewDidDisappear`/`finishRouteLifecycleForCoordinator`, `ChatRoomRouteLifecycleStateTests`. 최초70장 전송은 실패이며 사용자 최초 성공 답변은 정정됐다. 최신 수정·재검증 상태는 task progress 최상단을 따른다.

## 목적

기능 수정이나 새 기능 추가 시 AI 에이전트가 어디부터 봐야 하는지 빠르게 확인하기 위한 인덱스 문서다.

루트 문서는 공통 진입점과 세부 문서 링크만 유지한다. 기능별 상세 진입점은 필요한 문서만 추가로 읽는다.

## 공통 진입점

- iPhone 14 미디어 성능 QA: `OutPickTests/ChatMediaDevicePerformanceTests.swift` → `docs/ai/tasks/chat-media-bounded-parallel-upload/qa/iphone14-performance.md`. synthetic17회는 참고 자료이며 현재 `ChatMediaPipelineLimits.imagePreparation=4`는 실제 전송·스크롤 비교 후보다. 사용자가 실제 picker로 전송하고 Instruments Animation Hitches + Activity Monitor로 기록한다. ‘미디어 QA 방’ 실제 사진3장 ready/첨부3 확정 확인,70장 및2/4비교 진행 상태는 task progress 최상단. 영상은 후속, XCUITest 조작은 미검증.

- 미디어 제한 병렬 전송(2026-09-10 로컬 구현): `ChatViewController+MediaSelection.swift` → `ChatMediaSelectionUseCase`/`ChatMediaSelectionRepository` → `ChatMediaUploadTurnQueue`/`ChatMediaUploadUseCase` → `ChatOutgoingOutboxUseCase`. 전체 원본 확보 barrier, 준비·업로드 제한, queued 직후 실행권 반환, 중단 후 대표 실패 복원은 `entrypoints/CHAT.md`와 `tasks/chat-media-bounded-parallel-upload/`를 따른다. 서버 배포·실기기 QA는 별도다.

- 방별 자동 승계 50초 제한·부분 성공·실패 방 재처리: `functions/src/chat/moderation/{roomSuccessionPolicy,roomSuccessionJobs,roomMembershipSweep,roomMembershipSweepFunctions}.ts` → `firestore-tests/room-succession-deadline.emulator.test.mjs`; 상세는 `entrypoints/FIREBASE.md`와 `DATA_SCHEMA.md`
- 부모 승계 작업 장애 격리: `roomSuccessionJobs.ts`의 `parentFailurePatch/drainFailedParentRooms/terminalRoom`과 `roomMembershipSweepFunctions.ts` 예약 → 동일 deadline Emulator suite의 부모 실패·claim 경쟁·watchdog·replay 회귀. 실패한 부모의 진단은 자식 성공과 독립 보존한다.
- 채팅 역할 receipt·outbox TTL 배포 계약: `firestore.indexes.json` → `firestore-tests/room-role-indexes.contract.test.mjs`; 원격 배포 확인은 `entrypoints/FIREBASE.md` 참조
- 채팅 역할·읽음 최종 리뷰 회귀: `ChatMessage.init(from:)`, `ChatRoomRoleSession` → `OutPickTests/{RoomRoleEventPayloadTests,ChatRoomRoleSessionTests}.swift`; 세부 계약은 `entrypoints/{CHAT,TESTS}.md` 참조

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
- 채팅 메시지 신고 evidence 계약·transaction·copy/cleanup: `functions/src/moderation/messageEvidence/{contracts,service,evidenceCopy,evidenceStorage,evidenceCleanup,evidenceFunctions,evidenceRuntime}.ts` → `functions/src/index.ts` → `functions/scripts/qa-message-evidence-development.mjs` → `firestore.indexes.json` → `functions/src/moderation/reports/contracts.ts` → `contracts/chat-moderation-v1.json` → `functions/src/moderation/messageEvidence/{contracts,evidenceCopy}.test.ts` / `firestore-tests/moderation-reports.emulator.test.mjs`; Phase 7.4C-2/C-3은 Development bucket/IAM/세 Function/필수 인덱스 3개와 30장·350MiB E2E까지 완료했고 Rules·TTL·관리자 조회·Production은 후속 승인 gate다.
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
- Chat media Phase 7.0 feasibility worker: `tools/chat-media-processing-worker/src/index.ts` → `imageProcessor.ts`의 sharp/libvips JPEG·PNG·GIF 정규화와 raw HEIC/HEIF 거부, `videoProcessor.ts`의 ffprobe/ffmpeg stream-copy remux. animated GIF 출력은 `keepDuplicateFrames: true`로 연속 중복 frame까지 frame 수·delay·loop를 보존하며 `imageProcessor.integration.test.ts`가 회귀를 막는다. `runtimeVerification.ts`와 `benchmark.ts`가 codec·resource gate다. 사용자 HEIC 선택은 Phase 7.3 iOS가 고품질 JPEG로 준비한다.
- Chat media Phase 7.1 로컬 구현: Socket `mediaHandlers.js`/`mediaUploadService.js`의 v2 preflight·finalize·status·cancel → `Rooms/{roomID}/MediaUploads/{uploadID}` 단일 원장 → `functions/src/chat/media/`의 queue trigger·private dispatcher·고정 execution slot·watchdog → `tools/chat-media-processing-worker/src/cloudJob.ts`의 Quarantine download·정규화·ready staging manifest 기록. 전용 upload Rules는 `storage.chat-media-quarantine.rules`, client deny와 watchdog query/TTL은 `firestore.rules`/`firestore.indexes.json`이다. Phase 7.2 전에는 message·seq·broadcast를 만들지 않는다.
- Chat media Phase 7.2 로컬 구현: `functions/src/chat/media/readyService.ts`와 worker-completed trigger가 room seq transaction으로 message·media index·preview·delivery job·ready 상태를 원자 생성하고, 검증된 `actualFormat`·`frameCount`·`animated`를 attachment의 `mediaFormat`·`animated`로 투영한다 → `Socket/src/media/mediaDeliveryWatcher.js`가 job lease 후 기존 media event/FCM을 at-least-once 전달 → `reconcileChatMediaObjectCleanup`이 source·고아 ready cleanup을 재시도한다. 새 ready Storage read gate는 `storage.rules`, 전용 bucket deploy config는 `firebase.chat-media.json`, server-only job deny와 cleanup/TTL index는 `firestore.rules`/`firestore.indexes.json`이다.
- Chat media Phase 7.3 iOS 구현: `ChatImageTransportSourceNormalizer.swift`/`ChatMediaSelectionChunker.swift`가 metadata 제거·HEIC→JPEG·GIF 보존과 30장/150 MiB 분할 → `ChatMediaUploadTurnQueue.swift`/`ChatMediaUploadUseCase.swift`가 image/video 독립 FIFO, kind별 로컬 1건 실행, Socket `active_upload_limit` 동일 identity backoff와 relaunch `uploading` status-only 2·4·8초 reconciliation을 적용 → `ChatMediaForegroundUploadService.swift`가 이미지와 영상을 attachment당 하나의 V4 signed PUT으로 foreground direct upload·응답 유실 1회 서버 reconciliation·finalize/status 처리 → `ChatOutgoingOutboxUseCase.swift`/GRDB가 보호된 local source와 실패 후 재시도/삭제 계약을 보존하되 signed PUT URL·필수 header는 영속화하지 않음 → `ChatAttachmentImageService.swift`가 같은 이미지 upload source를 최대 1024px로 메모리 다운샘플링하고 animated viewer에 원본 data를 공급 → `ChatImagePreviewCell.swift`가 확정 GIF만 정적 thumbnail 우하단 `GIF` badge로 표시 → `SimpleImageViewerVC.swift`의 Kingfisher `AnimatedImageView`가 탭한 원본 GIF를 전체 frame 선로딩 없이 현재 page에서만 재생한다. `ChatPendingMediaUploadStore.swift`/`ChatViewController{,Extension}.swift`/`ChatMessageCell.swift`는 대기·활성·재실행 pending의 무표시 로컬 버블, failed/expired의 시간 위치 소형 재시도·삭제 아이콘과 ready delivery reconciliation을 담당한다. 일반 이미지·영상 실패는 전역 팝업 없이 버블 액션만 사용하고 ban 중단 안내만 유지한다. 미디어 실패 overlay, 전송 중 진행률·취소 UI와 background `URLSession`/자동 PUT 복원은 사용하지 않는다.
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
- iOS Chat background tap·native message context menu·announcement long press·cell action gesture 책임: `OutPick/Features/Chat/Controllers/{ChatViewController,ChatViewControllerExtension}.swift`, `OutPick/Features/Chat/Domain/Policies/ChatMessageActionPolicy.swift`, `OutPick/Features/Chat/Views/Cell/ChatMessageCell.swift`
- iOS Profile modal edge-swipe dismiss: `OutPick/Features/Profile/Views/UserProfileDetailViewController.swift`, `OutPick/Features/Profile/UserProfileDetailCoordinator.swift`, `OutPick/Infra/Utility/Transitions/ChatModalTransitionManager.swift`
- iOS visible Chat strict ordering/recovery: `OutPick/Infra/Realtime/RealtimeChatIngressOrdering.swift`, `OutPick/Infra/Realtime/FirebaseChatRealtimeGapRecoveryLoader.swift`, `OutPickTests/RealtimeChatIngressOrderingTests.swift`
- iOS lightweight Banner presentation/retry: `OutPick/Infra/Banner/BannerManager.swift`의 `RealtimeBackgroundRoomSessionOpening`·`BannerSubscriptionRetryPolicy`, `BannerPresentationQueueState.swift`, `OutPickTests/BannerPresentationQueueStateTests.swift`
- iOS 방별 fan-out 최종 dedupe: `OutPick/Infra/Realtime/RealtimeSocketService.swift`의 `ChatRoomSessionActor`, `OutPickTests/ChatRoomSessionActorTests.swift`
- Chat moderator delegation Phase 1 호환 데이터 기반: Room owner canonical/fallback은 `ChatRoom.swift` → `ChatRoomFirestoreDTO.swift` → `ChatRoomFirestoreMapper.swift`, role/read projection은 `JoinedRoomListItem.swift`, 공개 역할 이벤트 계약은 `ChatMessageType.swift`/`ChatMessage.swift`, 로컬 보존은 `ChatMessageRecord.swift` → `ChatMessageRecordMapper.swift` → `GRDBMigrationRegistry.addRoomRoleEventToChatMessage`다. 집중 검증은 `ChatRoomFirestoreMapperTests`, `JoinedRoomProjectionTests`, `RoomRoleEventPayloadTests`, GRDB mapper/migration tests다.
- Chat moderator delegation Phase 2 서버 권한 코어: `functions/src/chat/moderation/roomRoleService.ts`의 transaction resolver·임명/회수/사임/퇴장/이전·24시간 receipt·role event/outbox → `roomBanService.ts`/`service.ts`의 owner/moderator 제재 matrix → `functions.ts`/`functions/src/index.ts` callable export → `firestore.rules` private state·role mutation deny → iOS `ChatModerationLifecycleRepository.swift` access/mutation mapping. 검증은 `contracts.test.ts`, `index.contract.test.ts`, `firestore-tests/{chat-moderation.emulator,moderation-capabilities.rules.test}.mjs`, `CloudFunctionsChatModerationLifecycleRepositoryTests.swift`다.
- Chat moderator delegation Phase 5 자동 승계·계정 정리: 영구 정지/계정 삭제 transaction → `roomOwnershipSuccessionJobs` → `roomSuccessionJobs.ts`의 부모/방별 상태·계정 fence → `roomMembershipSweep.ts`의 관리자 전용 후보·no-candidate 종료 → `roomMembershipSweepFunctions.ts`의 방별 50초·실패 후 5/15/20초 예약과 5분 watchdog → account deletion `cleanup.ts`/`drain.ts` finalizer gate·role event 익명화 → iOS 동일 ID privacy 갱신. 수동 복구는 `functions/scripts/replay-room-ownership-succession.mjs --room ...`, 검증은 `room-succession-deadline.emulator.test.mjs`와 관련 suite다.
- Chat moderator delegation Phase 6 migration·rollout gate: `functions/scripts/migrate-room-moderator-cutover.mjs`가 dry-run/apply orchestration을, `room-moderator-cutover-plan.mjs`가 ownerUID·dual frontier·owner role·moderatorCount 보정 계획과 conflict/blocker·exact-count/hash gate를 소유한다. 앱 시작 gate는 `OutPick/App/Rollout/` → `AppCompositionRoot.swift` → `AppCoordinator.swift`, 채팅 화면 feature snapshot은 `ChatContainer` → `ChatCoordinator` → `ChatRoomSettingViewModel`, 서버 신규 권한 생성 gate는 `functions/src/chat/moderation/rollout.ts` → `functions.ts`다. fixture·gate 검증은 `room-moderator-cutover-plan.test.mjs`, `rollout.test.ts`, `AppRolloutGateTests.swift`, 운영 절차는 task `migration-runbook.md`다. 실제 Firebase migration·배포·설정 변경은 수행하지 않았다.
- Chat moderator delegation Phase 3 timeline/unread: Socket 일반 message는 `Socket/src/messages/sequenceStore.js`, media ready는 `functions/src/chat/media/readyService.ts`에서 `seq + unreadMessageSeq`를 원자 증가한다. 역할 outbox는 `Socket/src/roles/roleEventDeliveryWatcher.js` → `createProductionDependencies.js` → iOS `RealtimeSocketListenerBinder.swift`/`RealtimeSocketService.swift` 공통 ingress로 전달되고 Messages pagination이 복구 원장이다. iOS dual read frontier는 `ChatReadStateStore.swift`/`ChatRoomReadStateStore.swift`/`ChatRoomViewModel.swift` → `UserProfileRepository.updateReadFrontier`, 표시·제외 정책은 `RoomRoleEventCollectionViewCell.swift`, `ChatMessageActionPolicy.swift`, `BannerManager.swift`, `GRDBChatMessageStore.swift`가 소유한다.
- Chat moderator delegation Phase 4 iOS 역할 화면: 현재 방 단일 listener는 `ChatRoomRoleRepository.swift` → `ChatRoomRoleUseCase.swift` → `ChatRoomRoleSession.swift`이며 `ChatContainer`가 같은 세션을 `ChatRoomViewModel`과 `ChatRoomSettingViewModel`에 주입한다. 참여자 pinned pagination·정렬은 `FirebaseChatRoomRepository.fetchPinnedRoomMembers` → `LoadChatRoomParticipantsUseCase`, 임명·회수·사임·이전 UI는 `ChatRoomSettingViewController`, 메시지 작성자 현재 역할 지연 판정은 `ChatRoomViewModel.resolvedMessageActionPolicy` → `ChatMessageActionPolicy`다. 검증은 `ChatRoomRoleSessionTests`, `ChatRoomParticipantRolePolicyTests`, `ChatMessageActionPolicyTests`, `ChatRoomExitUseCaseTests`다.
- 현재 Socket ingress 순서 보장 task: `docs/ai/tasks/socket-ingress-ordering-hardening/`
- iOS Socket candidate QA: `RealtimeSocketService.swift`의 DEBUG 전용 `SocketDebugQAConfiguration`, `OutPickTests/SocketDebugQAConfigurationTests.swift`
- iOS 발신 ACK 수렴: `ChatMessageSendReceipt.swift`, `ChatViewController.reconcileServerConfirmedOutgoingMessage`, `LookbookChatShareViewModel`의 동일 ID retry
- Socket room summary 단일 소유권: `Socket/src/messages/sequenceStore.js`가 seq transaction 안에서 `Rooms.lastMessage*`를 갱신하며, iOS `RealtimeSocketService`의 ACK 경로는 room summary를 직접 쓰지 않는다.
- Socket 자동 검증: `Socket/test/`, `Socket/scripts/run-tests.mjs`
- Phase 6 텍스트 전송 보호: Socket `src/utils/rateLimit.js`와 text/Lookbook/media handler가 canonical moderation principal·room·kind별 2초 bucket을 공유하고, Functions `src/lookbook/comments/{contracts,service,functions}.ts`가 댓글·답글 합산 분당 20회 Firestore transaction quota와 UUID 멱등 문서 ID를 소유한다. iOS 입력 상한/재시도 ID는 `ChatRoomMessageUseCase.swift`, `ChatUIView.swift`, `Create{PostComment,CommentReply}UseCase.swift`, 댓글 ViewModel/InputBar가 담당한다.
- Phase 6 메시지 개인정보 최소화: 신규 메시지의 `senderEmail`은 Socket/FCM/iOS `ChatMessage`/GRDB에서 제외하며 `GRDBMigrationRegistry.removeSenderEmailFromChatMessage`가 기존 로컬 column을 제거한다.
- Chat UGC safety/moderation v1 계약: `contracts/chat-moderation-v1.json` → ADR-024 → `docs/ai/tasks/chat-ugc-safety-room-moderation/{decisions,plan,phase-7-implementation-plan,progress,qa-checklist}.md`
- Chat moderation Phase 1 구현·Development rollout: iOS `CloudFunctionsCurrentUserModerationRepository`/`LoadCurrentUserBootstrapUseCase`/`AppCoordinator`/`ModerationNoticeViewController`, Functions `src/moderation/`와 `scripts/backfill-moderation-principals.mjs`, Socket `src/moderation/capabilities.js`, `firestore.rules`/`storage.rules` → 상세 `entrypoints/APP.md`, `entrypoints/CHAT.md`, `entrypoints/FIREBASE.md`, `entrypoints/TESTS.md`
- Chat moderation Phase 2 신고·관리자 API: iOS `ChatModerationReport.swift` → `ChatModerationReportingRepository.swift` → `SubmitChatModerationReportUseCase.swift`; Functions `src/moderation/{reports,admin,audit}/`; Rules/index/transaction QA `firestore.rules`, `firestore.indexes.json`, `firestore-tests/moderation-{capabilities.rules,reports.emulator}.test.mjs`
- Chat deletion revision legacy 감사·cutover: `functions/scripts/audit-chat-deletion-revisions.mjs`가 revision·cleanup·reply/media 잔존을 읽기 전용·비식별 집계한다. `apply-chat-deletion-field-index.mjs`는 Development 단일 field index를 exact patch하고, `repair-chat-deletion-cutover.mjs`는 expected hash/count/head와 confirmation fence 아래 cleanup 재개·revision backfill을 분리 수행한다. 순수 gate/정렬은 `chat-deletion-cutover-plan.mjs`와 test가 소유한다.
- Chat moderation Phase 3 삭제·Phase 3.1 공용 종료 tombstone: iOS `FirebaseChatRoomRepository.fetchJoinedRoomList`/`ChatModerationLifecycleRepository.swift` → `ChatRoomClosureAcknowledgementUseCase`/`JoinedRoomsViewModel`/`ChatCoordinator.handleRoomClosure`; 실시간·오프라인 확인 직후 목록 제거와 같은 세션 stale fetch 차단은 `ChatRoomClosureListUpdating`, `JoinedRoomsViewModel.removeRoomAfterRealtimeClosure`/`acknowledgeClosedRoom`; Functions `src/chat/{moderation,cleanup}/`의 `acknowledgeRoomClosure`와 `content → retention` cleanup; Socket `roomClosureWatcher.js`; Rules/transaction QA `firestore-tests/{moderation-capabilities.rules,chat-moderation.emulator}.test.mjs`
- Chat moderation Phase 4 전역 차단: `OutPick/Features/Moderation/{UserBlockVisibilityStore,UserBlockSnapshotStore,UserBlockSessionController}.swift` → `AppCompositionRoot`/`AppCoordinator` bootstrap → Chat·Lookbook·Profile·MyPage 공용 UseCase/Store; Functions `src/lookbook/safety/{blockContracts,functions}.ts`의 `blockUser`/`unblockUser`; Socket `src/push/chatPushService.js`의 수신자별 차단 push 억제 → 상세 `entrypoints/{APP,CHAT,FIREBASE,TESTS}.md`
- Chat moderation Phase 7.4D 관리자 queue/current-revision Evidence: Functions `src/moderation/admin/{contracts,service,functions,messageResolution,evidenceAccess}.ts`, Evidence retention drain `src/moderation/messageEvidence/{evidenceCleanup,evidenceFunctions}.ts`, Firestore deny/index/TTL `firestore.{rules,indexes.json}`, 전용 Storage target/rules `.firebaserc`·`firebase.chat-media.json`·`storage.moderation-evidence.rules`, 자동 검증 `functions/src/moderation/admin/*.test.ts`·`firestore-tests/{moderation-reports.emulator,moderation-evidence-storage.rules.test}.mjs` → 상세 `entrypoints/{FIREBASE,TESTS}.md`
- Chat moderation Phase 7.5E 사용자 메시지 신고: `ChatViewController.handleReport`와 `SimpleImageViewerVC.onReport` → `ChatCoordinator.presentMessageReport` → `ChatMessageReportViewController`/`ChatMessageReportViewModel` → `SubmitChatModerationReportUseCase.submitMessageReport` → `CloudFunctionsChatModerationReportingRepository` → callable `submitMessageReport`/`submitMessageReportService`. 중복 판정은 서버 transaction이 소유하고 iOS는 별도 GRDB·신고 캐시 없이 현재 신고 화면의 네트워크 재시도 동안만 UUID와 입력을 유지한다. 신고 화면은 OutPick editorial token을 사용하며 상세 입력 밖 tap과 scroll drag로 키보드를 닫는다. `신고` CTA는 사유 선택 전 비활성이고 선택 직후 활성화되며 ViewModel도 사유 누락을 재검증한다. reason title·symbol, multiline 안내·placeholder와 가변 높이 CTA는 Dynamic Type에 맞춰 재구성되고 선택·제출 상태는 글자 크기 변경 중에도 유지한다.
- Chat moderation Phase 7.5A~D queue-only·공통 deletion mutation·Socket fast path·iOS reconciliation: 서버는 `functions/src/chat/deletion/mutation.ts`, Socket은 `Socket/src/deletion/deletionDeliveryWatcher.js`, iOS는 `ChatDeletionSyncUseCase.swift` → `ChatDeletionSyncRepository.swift` → `GRDBChatDeletionSyncStore.swift` → `ChatMessageRecordMapper.swift`를 진입점으로 사용한다. 최초 삭제만 tombstone·Room revision·cleanup/outbox를 원자 생성하며 iOS는 account+room cursor·방 수명 삭제 마커·durable cleanup queue로 누락을 복구한다. 서버가 직접 반환한 같은/더 최신 tombstone은 legacy marker의 sender 익명화 정책을 교정하고, 오래된 visible payload에는 marker가 계속 우선한다. 기존 Firestore 삭제 listener는 제거됐다.
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
| Chat 신고·차단·삭제·room ban·계정 제재·미디어 격리/evidence | `tasks/chat-ugc-safety-room-moderation/decisions.md` → Phase 7.5 신고 UX·Deletion Sync `phase-7-5-design.md` → `phase-7-implementation-plan.md` → `contracts/chat-moderation-v1.json` → ADR-024 → `CHAT.md`/`FIREBASE.md`/`TESTS.md` → task plan/progress/QA |
| Chat route/lifecycle/gesture 완료 변경 | `CHAT.md`의 `Route/lifecycle/gesture 변경 파일 빠른 지도` → `tasks/chat-route-lifecycle-hardening/progress.md` → `TESTS.md`의 Chat route lifecycle hardening tests → task QA checklist |
| Firestore 문서 identity | ADR-020 → `DATA_SCHEMA.md` → `CHAT.md`/`LOOKBOOK.md` 문서 ID 경계 → `DATA.md` Repository boundary → `FIREBASE.md` rules → `TESTS.md` 경계 테스트 → task progress/QA |
| Chat 대규모 unread/read frontier | `tasks/active.md` → `tasks/socket-ingress-ordering-hardening/phase-6-unread-catch-up-read-frontier.md` → `CHAT.md` read frontier/realtime-only 3초 preview·즉시 persistence 및 진단 계측 진입점 → `TESTS.md` Phase 6-A~C 회귀·Phase 6-D QA |

작업 시작 시 이 문서와 `docs/ai/tasks/active.md`만 먼저 읽고, 표가 가리키는 세부 문서만 추가로 확인한다.
