# OutPick Entrypoints

## 목적

기능 수정이나 새 기능 추가 시 AI 에이전트가 어디부터 봐야 하는지 빠르게 확인하기 위한 인덱스 문서다.

루트 문서는 공통 진입점과 세부 문서 링크만 유지한다. 기능별 상세 진입점은 필요한 문서만 추가로 읽는다.

## 공통 진입점

- 앱 시작/루트 라우팅: `OutPick/App/AppCoordinator.swift`
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
- Firebase Functions 기능 구현: `functions/src/{auth,brand,chat,lookbook}/`
- Lookbook import extraction core/evidence/version: `tools/lookbook-import-worker/src/extraction/`, `processor.ts`, `season-discovery.ts`
- Lookbook extraction adapter registry: `tools/lookbook-import-worker/src/extraction/adapters/{registry,cafe24,types}.ts`
- Lookbook extraction review/trust/resume: worker `src/extraction/review.ts`, Functions `src/lookbook/import/{functions,reviewContract}.ts`, iOS `LookbookExtractionReview*`
- Lookbook extraction count-based review gate/UI: worker `src/extraction/{quality,review}.ts`, iOS `LookbookExtractionReview.swift`, `LookbookExtractionReviewViewModel.swift`, `LookbookExtractionReviewView.swift`
- Lookbook expected-count 활성 gallery scope: worker `src/extraction/expected-count.ts`, YOUTH incident fixture/test
- Lookbook 시즌 상세 pagination·이미지 prefetch: `LoadSeasonDetailUseCase.swift`, `SeasonDetailViewModel.swift`, `SeasonDetailView.swift`, 공용 `BrandImageCache`→`ImageCachePipeline`
- Lookbook extraction evidence/issue cluster: worker `src/extraction/retained-evidence.ts`, Functions `src/lookbook/import/evidenceCleanup.ts`
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
| Chat membership/cache | `CHAT.md` → `DATA_SCHEMA.md` Chat 계약 → 관련 task decisions/progress |
| Chat route/lifecycle/gesture 완료 변경 | `CHAT.md`의 `Route/lifecycle/gesture 변경 파일 빠른 지도` → `tasks/chat-route-lifecycle-hardening/progress.md` → `TESTS.md`의 Chat route lifecycle hardening tests → task QA checklist |
| Firestore 문서 identity | ADR-020 → `DATA_SCHEMA.md` → `CHAT.md`/`LOOKBOOK.md` 문서 ID 경계 → `DATA.md` Repository boundary → `FIREBASE.md` rules → `TESTS.md` 경계 테스트 → task progress/QA |
| Chat 대규모 unread/read frontier | `tasks/active.md` → `tasks/socket-ingress-ordering-hardening/phase-6-unread-catch-up-read-frontier.md` → `CHAT.md` read frontier/realtime-only 3초 preview·즉시 persistence 및 진단 계측 진입점 → `TESTS.md` Phase 6-A~C 회귀·Phase 6-D QA |

작업 시작 시 이 문서와 `docs/ai/tasks/active.md`만 먼저 읽고, 표가 가리키는 세부 문서만 추가로 확인한다.
