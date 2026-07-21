# Test Entrypoints

## 공통

- 단위 테스트: `OutPickTests`
- UI 테스트: `OutPickUITests`
- 앱 빌드 기본 검증:

```bash
xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build
```

- Phase 6 통합 회귀: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-integration-tests.md`
- Phase 6 배포·smoke gate: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-deployment.md`
- Phase 6는 Phase 2~5 targeted test, iOS generic build, Functions test/lint/build와 Socket check/test를 같은 배포 commit SHA 기준으로 실행한다.
- Firestore rules emulator: `firestore-tests/room-document-id.rules.test.mjs`
  - room/member/joinedRooms 원자 transaction과 Rooms `ID`/`id` create/update 차단을 검증한다.
  - 실행: `cd firestore-tests && npm install && npm test`.

## Lookbook

- iOS Cloud Functions 계약 테스트: `OutPickTests/CloudFunctions/`
  - 공통 decoder와 transport spy, Auth/Admin capability, Brand/Request, Engagement/Comment, Import/Deletion의 사용 callable 38개를 검증한다.
  - 실제 Firebase 서버를 호출하지 않고 function name, payload, response mapping과 오류 보존을 고정한다.

- Lookbook interaction/store tests: `OutPickTests/LookbookInteractionStoreTests.swift`, `OutPickTests/LookbookDebugFailureInjectionStoreTests.swift`
- Lookbook detail tests: `OutPickTests/PostDetailScreenViewModelTests.swift`, `OutPickTests/SeasonDetailViewModelTests.swift`
- 좋아요 탭 tests: `OutPickTests/LikedViewModelTests.swift`, `OutPickTests/LoadLikedSeasonsUseCaseTests.swift`
- 삭제 요청 관리 pagination/retry tests: `OutPickTests/AdminLookbookDeletionManagementViewModelTests.swift`
- Firestore 문서 ID 경계: `OutPickTests/FirestoreDocumentIDBoundaryTests.swift`
  - 저장된 legacy `id`보다 경로 ID가 우선하는지, 빈 경로 ID가 실패하는지, Season write payload에 `ID`/`id`가 없는지 검증한다.
  - 실행: `xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'platform=iOS Simulator,id={simulator-id}' -only-testing:OutPickTests/FirestoreDocumentIDBoundaryTests test`.
  - 2026-07-14 Phase 4에서 영향 범위 11개 suite의 runtime test 59개, Firestore Emulator 11개, generic Simulator build와 test target build-for-testing이 통과했다. 실제 로그인 QA에서도 Chat/Lookbook read·write 경계와 `I-FST000002` 0건을 확인했다.
  - rules 운영 배포와 Rooms legacy `ID` 4건 cleanup 후 재감사에서 `ID`/`id` 보유 0건, 방 4개 유지, 핵심 불변식 누락 0건과 로그인 앱 목록 read를 확인했다.
- UI smoke/failure tests: `OutPickUITests/LookbookSmokeUITests.swift`, `OutPickUITests/LookbookInteractionFailureToastUITests.swift`
- UI test support/robots: `OutPickUITests/LookbookUITestSupport.swift`, `OutPickUITests/LookbookPostDetailRobot.swift`, `OutPickUITests/LookbookCommentsRobot.swift`

Lookbook import worker tests:

- `tools/lookbook-import-worker/src/processor.test.ts`
- `tools/lookbook-import-worker/src/job-lifecycle.test.ts`
- `tools/lookbook-import-worker/src/public-http.test.ts`
- `tools/lookbook-import-worker/src/config.test.ts`

Firebase Functions tests/build entry:

- Phase 4 Functions 모듈화 테스트 계획: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-4-firebase-functions-tests.md`
  - 구현 시 49개 export/`__endpoint` metadata, 초기화 owner, 재귀 test discovery, feature policy와 고위험 service failure를 검증한다.
- Functions package: `functions/package.json`
- Functions source: `functions/src`
- export/runtime 계약: `functions/src/index.contract.test.ts`
- 초기화 owner/import 방향/root 구조 계약: `functions/src/architecture.contract.test.ts`
- Lookbook deletion purge lease: `functions/src/lookbook/deletion/purgeLease(.test).ts`
- Lookbook deletion purge drain: `functions/src/lookbook/deletion/purgeDrain(.test).ts`
- 기능 단위 테스트: `functions/src/{auth,brand,chat,lookbook}/**/*.test.ts`
- `functions/package.json`의 `npm test`는 clean build 후 `lib/` 아래 `*.test.js`를 재귀 발견해 실행하며 0개면 실패한다.
- 실행: `cd functions && npm test`
- purge drain 핵심 시나리오: 20개 초과 page 반복, 서로 다른 브랜드 최대 3개, 같은 브랜드 순차, 부모 target 우선, 실패/lease skip 후 계속 처리, 7분 cutoff.
- 운영 통합 결과와 남은 관찰 항목: `docs/ai/tasks/lookbook-deletion-purge-drain/progress.md`, `qa-checklist.md`.
- Functions workflow: `.codex/skills/firebase-functions-workflow/SKILL.md`

## Chat / Realtime

- Phase 6-A read frontier/catch-up state: `OutPickTests/ChatReadStateStoreTests.swift`, `OutPickTests/ChatUnreadCatchUpStateTests.swift`
  - seeded monotonic frontier, visible candidate의 연속 상한, explicit gap 승인과 window 없는 final frontier를 검증한다.
  - scalar unread count, 고정 target, generation 기반 stale/중복/실패 거부와 10,000개 latest event payload 비보관을 검증한다.
  - 2026-07-17 iPhone 15 Pro iOS 17.2 Simulator에서 2개 suite 19개 테스트와 generic Simulator build가 통과했다.

- Phase 6-B bounded catch-up/persistence: `OutPickTests/ChatLatestMessageWindowTests.swift`, `ChatRoomMessageUseCaseTests.swift`, `ChatOutgoingOutboxUseCaseTests.swift`, `ChatRoomViewModelMessageActionTests.swift`
  - 고정 80개 server-authoritative target query, `Int64.max` 분기, target 이하 정규화·누락 실패를 검증한다.
  - 10,000개 catching-up incoming의 scalar-only 상태, manager 저장 성공 이후 outbox reconciliation, 서버 확정 ID batch 삭제를 검증한다.
  - 2026-07-17 iPhone 15 Pro Simulator에서 4개 suite 22개 테스트와 generic iOS Simulator build가 통과했다.

- Phase 6-C latest UI/read handshake state: `OutPickTests/ChatReadStateStoreTests.swift`, `ChatUnreadCatchUpStateTests.swift`, `ChatLatestMessageWindowTests.swift`, `ChatMessageWindowStoreTests.swift`, `ChatRoomViewModelMessageActionTests.swift`
  - realtime 없는 initial entry tail preview 상태, target/preview 동시 고정과 이후 신규 seq 잔존, 표시 실패/retry, visible 연속 상한과 window-independent final frontier를 검증한다.
  - latest window 교체의 서버 확정 ID 우선과 unresolved failed local message 보존, 날짜 separator/300개 virtualization 회귀를 검증한다.
  - explicit 이동 표시 성공 뒤 즉시 server persistence, server 성공 이후 shared mark, 실패 pending 보존을 lifecycle spy로 검증한다.
  - 2026-07-17 iPhone 17 Pro Max Simulator에서 5개 suite 고유 테스트 48개와 앱 전체 Simulator build가 통과했다. 실제 Firebase pop/re-entry persistence, preview card·keyboard/reply/notice 충돌과 VoiceOver는 Phase 6-D 수동 재QA 대상이다.
  - 후속 initial preview sender 계약으로 local profile cache hit의 닉네임+내용과 cache miss의 nil sender fallback 테스트 2개를 `ChatRoomViewModelMessageActionTests`에 추가했다. 프로젝트 실행 원칙에 따라 새 테스트 실행은 보류했고 2026-07-17 iPhone 17 Pro Max Simulator 앱 build는 통과했다.
  - 2026-07-17 최종 제품 결정으로 위 initial preview 테스트 계약을 폐기하고 `initialEntryTailShowsLatestJumpWithoutRealtimeEvent`와 local profile cache 테스트를 제거·반전했다. no-realtime 미표시, realtime 닉네임+내용, sender 누락 fallback, dismiss 시 unread 불변과 stale timer target 방어 테스트를 추가했다. Phase 6 관련 5개 suite 52개를 실행해 실패·skip 0개로 통과했다. 실제 3초 경과와 pop/re-entry 비복원은 두 Simulator 수동 QA도 통과했으며 diffable visible target 억제는 남아 있다.
  - persistence 계측 추가 뒤 동일 5개 suite 52개를 재실행해 실패·skip 0개로 통과했다. explicit 성공은 authoritative readback 호출을, write 실패는 readback 미호출을 spy로 검증한다. 계측 추가 빌드도 iPhone 17 Pro Max Simulator에서 성공했다.
  - initial latest 위치 수정 중 같은 52개 테스트를 다시 실행해 실패·skip 0개를 확인했다. 최종 UIKit-only reload/layout-settle 변경은 Simulator build와 실제 Firebase `lastRead/latest=92`, `999999` 재진입 화면으로 수동 검증했다.

- iOS Socket listener 안정화 test: `OutPickTests/RealtimeSocketListenerBinderTests.swift`
  - client event 3개와 named event 5개의 최초 1회 등록, 같은 binder 재호출 무효, 반복 connect callback 중 등록 수 불변, 새 Socket/binder 독립 등록과 payload 전달을 검증한다.
  - Phase 1의 mixed message event FIFO와 queue 종료, joined-room 공통 ID admission의 room 분리·local seq 0 우회·300개 eviction·reset, background high watermark promotion과 stale visible lease 종료 거부를 검증한다.
  - 실행: `xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'platform=iOS Simulator,id={simulator-id}' -only-testing:OutPickTests/RealtimeSocketListenerBinderTests test`.
  - 2026-07-16 `RealtimeSocketListenerBinderTests`와 `ChatRoomSessionActorTests` 대상 19개 테스트가 iPhone 15 Pro iOS 17.2 Simulator에서 통과했다.
  - 실제 reconnect gate는 cold launch 5회와 background/foreground 5회, room rejoin/text 중복 부재와 credential raw log 부재를 확인한다. 상세 절차는 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-ios-socket-stabilization.md`에 있다.

- Phase 5 Socket 테스트 계획: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-5-socket-tests.md`
  - `Socket/test/`에서 application/architecture, auth, room/message/media handler와 service, lifecycle/runtime/state 계약을 검증한다.
  - `Socket/scripts/run-tests.mjs`는 모든 `*.test.js`를 재귀 발견하며 0개 test를 실패 처리한다.
  - 실행: `npm --prefix Socket run check`, `npm --prefix Socket test`.
  - 2026-07-14 syntax check와 43개 `node:test`, ADC 기반 room preload/health/graceful shutdown local smoke가 통과했다. Cloud Run/iOS 실제 송수신 smoke는 미수행이다.

- Socket message dedupe Phase 1~2 tests: `Socket/test/messages/messageDeliverySingleFlight.test.js`, `Socket/test/messages/sequenceStore.test.js`, `Socket/test/handlers/messageHandlers.test.js`, `Socket/test/lookbookShare/lookbookShareHandler.test.js`, `Socket/test/handlers/mediaHandlers.test.js`, `Socket/test/media/mediaUploadService.test.js`
  - 동일 identity owner/follower 병합, kind/room/message key 분리, 실패 공유·entry 해제·재시도를 검증한다.
  - 신규 transaction `{ seq, created: true }`, 기존 message `{ seq, created: false }`, duplicate no-write와 winner-only emit/push를 검증한다.
  - media 완료 retry의 sender/kind/path 검증, reservation 삭제 race 재확인과 독립 coordinator transaction loser를 검증한다.
  - 2026-07-16 closeout에서 syntax check와 전체 62개 테스트를 다시 통과했다.
  - 2026-07-15 `npm --prefix Socket run check`와 Socket 전체 62개 `node:test`가 통과했다.

- Chat route lifecycle hardening tests: `OutPickTests/ChatNavigationStackPolicyTests.swift`, `ChatOpenRoomRequestStateTests.swift`, `ChatOpenRoomRequestRegistryTests.swift`, `ChatRoomRouteLifecycleStateTests.swift`
  - 같은 stack의 기존 Chat route 교체와 non-Chat prefix 보존, top same-room no-op를 검증한다.
  - stack별 요청 격리, same-room 실제 Task 공유, same-stack latest-wins, stale 성공·실패 무시와 실패 후 재시도를 검증한다.
  - terminal route가 `didAppear`로 부활하지 않고 transient binding 복구 대상에서 제외되는 lifecycle 계약을 검증한다.
  - 2026-07-21 관련 고유 시나리오 20개와 generic Simulator build가 통과했다. 탭별 stack/Back/deinit과 룩북 이동 loading·닫기 잠금은 로그인 Simulator 수동 QA가 남아 있다.

- iOS message ingress dedupe Phase 3 tests: `OutPickTests/ChatRoomSessionActorTests.swift`
  - 한 명/두 명 consumer의 동일 ID 단일 전달, 종류와 무관한 ID 정책, 같은 ID·다른 seq first-wins, 실제 300개 oldest eviction과 actor 재생성 reset을 검증한다.
  - 로컬 실패 메시지가 같은 ID의 후속 서버 확인 event를 차단하지 않는 source 분리도 검증한다.
  - 2026-07-15 신규 actor 6개와 `ChatMessageWindowStoreTests`, `GRDBChatMessageStoreTests`, `RealtimeSocketListenerBinderTests` 회귀를 합친 고유 테스트 20개, generic Simulator build가 통과했다.
  - 공통 admission은 Phase 1에서 구현했다. Phase 2·3 strict seq/recovery와 Phase 4 suspend/rejoin 감사·terminal 종료는 `OutPickTests/RealtimeChatIngressOrderingTests.swift`, Banner hard-cap summary는 `OutPickTests/BannerPresentationQueueStateTests.swift`, baseline 전달은 `ChatRoomRealtimeUseCaseTests.swift`, 실제 route 판정은 `ChatRoomRouteLifecycleStateTests.swift`에서 검증한다.
  - Phase 5 차단 결함 회귀는 `ChatMessageWindowStoreTests`의 same-day/cross-day older·newer separator identity, `RealtimeRoomJoinStateTests`의 concurrent join/stale ACK/reconnect invalidation, `BannerSubscriptionRetryPolicyTests`의 capped backoff와 recoverable 재구독으로 검증한다. 관련 17개 suite 87개 테스트와 generic Simulator build가 2026-07-16 통과했다.
  - room-close 최종 회귀는 `RealtimeSocketListenerBinderTests`의 authoritative closure 선행/observer 후행 replay와 same-room create reset, room-not-found ACK mapping, `ChatRoomRuntimeUseCaseTests`, `ChatRoomRouteLifecycleStateTests`로 검증한다. 2026-07-17 대상 테스트가 통과했다.
  - 실제 QA는 셀룰러 iPhone 14 disconnect/reconnect의 `680001 → 680004`, `990001` leave 목록 제거, room close 자동 route 종료와 Cloud Run 종료 후 join 재시도 0회까지 통과했다.

- Socket candidate QA configuration tests: `OutPickTests/SocketDebugQAConfigurationTests.swift`
  - DEBUG 전용 candidate URL override의 유효 URL 선택·잘못된 값 production fallback과 message kind별 첫 성공 ACK 유실 설정을 검증한다.
  - launch environment key는 `OUTPICK_DEBUG_SOCKET_URL`, `OUTPICK_DEBUG_DROP_FIRST_MESSAGE_ACK_KIND`이며 Release에서는 코드가 컴파일되지 않는다.
  - 2026-07-15 신규 3개와 ingress actor 6개 targeted test, Release generic Simulator build가 통과했다.

- iOS send receipt tests: `OutPickTests/ChatMessageEmitAckMapperTests.swift`, `ChatOutgoingOutboxUseCaseTests.swift`, `LookbookChatShareUseCaseTests.swift`
  - ACK의 identity/seq/duplicate 파싱, matching message 실패 해제와 서버 attachment 병합, identity mismatch 거부를 검증한다.
  - outbox 유무와 관계없는 서버 확정 GRDB 저장과 Lookbook 결과 불명 retry의 동일 message ID 재사용을 검증한다.
  - 2026-07-15 receipt 영향 범위 9개 suite test, test target build-for-testing, Debug/Release generic Simulator build가 통과했다.

- Socket room summary ownership regression: `OutPickTests/RealtimeSocketRoomSummaryOwnershipTests.swift`
  - Socket ACK 이후 iOS가 `updateRoomLastMessage`를 호출하지 않고 서버 seq transaction만 `Rooms.lastMessage*`를 쓰는 source 계약을 검증한다.
  - 2026-07-15 기존 ACK mapper/outbox/Lookbook suite와 합친 targeted test 26개와 양쪽 Simulator Debug build가 통과했다.

- App database bootstrap unit tests: `OutPickTests/AppBootstrapFailureInjectorTests.swift`, `OutPickTests/AppCompositionRootTests.swift`
  - DEBUG once/always 실패 주입 상태와 database factory 오류 mapping을 검증한다.
- App database bootstrap UI tests: `OutPickUITests/AppBootstrapFailureUITests.swift`
  - 실제 DB 손상 없이 실패 root, once 재시도 성공, always 반복 실패·앱 생존을 검증한다.

- Phase 3 GRDB 테스트 계획: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-3-grdb-tests.md`
  - temporary `AppDatabase` fixture로 production DB를 열지 않는다.
  - 15개 fresh migration, mapper, message/FTS/media strict rollback, outbox, profile LRU, transient/exit cleanup transaction을 검증한다.
  - 구현 파일: `OutPickTests/GRDB/`의 migration/mapper/Store 7개 test suite와 `TestSupport/TemporaryAppDatabase.swift`.
  - 관련 UseCase/Manager 회귀: `ChatOutgoingOutboxUseCaseTests`, `ChatProfileSyncManagerTests`, `ChatRoomExitUseCaseTests`.
  - 2026-07-13 targeted test 묶음과 generic Simulator build가 통과했다. 수동 QA는 미수행이다.

- Image viewer unification verification:
  - Task QA checklist: `docs/ai/tasks/image-viewer-unification/qa-checklist.md`
  - Phase progress and performed verification: `docs/ai/tasks/image-viewer-unification/progress.md`
  - Pure policy tests: `OutPickTests/ImageViewerPagePolicyTests.swift`
    - `ChatImagePreviewItem.previewPaths` thumb/original ordering and duplicate local pending path handling.
    - `ChatMessage.displayableAttachments` sorting/filtering contract used by chat preview/viewer mapping.
    - `ImageViewerPage` local-only initial image contract and `SimpleImageViewerVC.ProgressivePage` compatibility alias.
  - 기본 회귀 확인은 1장/30장/pending/final/빠른 paging/manual save QA와 `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`를 기준으로 한다.
- Image viewer targeted test:

```bash
xcodebuild -scheme OutPick -destination 'platform=iOS Simulator,name={simulator}' test -only-testing:OutPickTests/ImageViewerPagePolicyTests
```

- Joined rooms session store tests: `OutPickTests/JoinedRoomsSessionStoreTests.swift`
  - `JoinedRoomsSessionStore` snapshot API, replace/add/remove/clear/contains 동작을 확인한다.
- Room exit use case tests: `OutPickTests/ChatRoomExitUseCaseTests.swift`
  - socket leave/close 성공/실패, local cleanup, joined room remove 경로를 확인한다.
- Chat room Firestore mapper tests: `OutPickTests/ChatRoomFirestoreMapperTests.swift`
  - 경로 document ID 우선, 핵심 필드 검증, ancillary 기본값과 identity-free write payload를 확인한다.
- Create room use case tests: `OutPickTests/CreateRoomUseCaseTests.swift`
  - duplicate 차단, Repository 반환 room 이벤트, 저장 실패 시 이벤트 미발행을 확인한다.
- Media upload tests: `OutPickTests/ChatMediaUploadUseCaseTests.swift`
  - image/video upload orchestration, preflight/finalize 실패, pending/outbox 연동을 확인한다.
  - 동기 socket connected guard가 아니라 preflight/finalize ACK 실패 경로를 검증한다.
- Outgoing outbox tests: `OutPickTests/ChatOutgoingOutboxUseCaseTests.swift`
  - 실패 message 복원, retry, local-only delete, uploaded media cleanup을 확인한다.

최근 targeted test 예시:

```bash
xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/JoinedRoomsSessionStoreTests
xcodebuild -scheme OutPick -destination 'id=5A3BB941-9538-4DD9-93C2-F18ACCFB03B9' test -only-testing:OutPickTests/ChatRoomExitUseCaseTests -only-testing:OutPickTests/JoinedRoomsSessionStoreTests
```
