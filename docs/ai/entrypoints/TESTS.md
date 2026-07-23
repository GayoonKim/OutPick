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
  - 시즌 상세는 24개 초기 page, 마지막 12개 trigger, page 간 PostID 중복 제거, 동시 호출 병합, 빈 visibility page 연속 조회, refresh race와 실패 재시도를 검증한다.
  - 이미지 prefetch는 첫 12개·현재 위치 앞 32개·concurrency 4, append 직후 새 page 24개 등록, 반복 카드 노출의 경로 중복 방지를 `SeasonDetailBrandImageCacheSpy`로 검증한다.
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

- `tools/lookbook-import-worker/src/extraction/core.test.ts`
- `tools/lookbook-import-worker/src/extraction/adapter-registry.test.ts`
- `tools/lookbook-import-worker/src/extraction/review.test.ts`
- `tools/lookbook-import-worker/src/extraction/retained-evidence.test.ts`
- `tools/lookbook-import-worker/src/extraction/youth-fixture.test.ts`
- `tools/lookbook-import-worker/fixtures/season-images/incidents/youth-programmatic-gallery/`
- `tools/lookbook-import-worker/src/fixture/corpus.test.ts`
- `tools/lookbook-import-worker/src/fixture/run-corpus.ts`
- `tools/lookbook-import-worker/fixtures/{discovery,season-images}/`
- `tools/lookbook-import-worker/fixtures/discovery/platform/cafe24-underscore-detail-list/`
- `tools/lookbook-import-worker/src/processor.test.ts`
- `tools/lookbook-import-worker/src/job-lifecycle.test.ts`
- `tools/lookbook-import-worker/src/public-http.test.ts`
- `tools/lookbook-import-worker/src/config.test.ts`
- 실행: `cd tools/lookbook-import-worker && npm test` (root와 하위 test 모두 포함, extraction review 수량 기준 보완 후 66/66 통과).
- fixture gate: `cd tools/lookbook-import-worker && npm run test:fixtures` (외부 fetch 없이 현재 corpus 5/5와 구조화된 differential을 검증).
- extraction review Functions contract: `functions/src/lookbook/import/reviewContract.test.ts`, `taskService.test.ts`, `importValidation.test.ts`, `functions/src/index.contract.test.ts`.
- extraction review iOS targeted tests: `OutPickTests/LookbookExtractionReviewViewModelTests.swift`, `OutPickTests/CloudFunctions/CloudFunctionsSeasonImportRepositoryTests.swift`.
- existing-season reconcile: worker `src/extraction/reconcile.test.ts`, Functions `repairContract.test.ts`, iOS `LookbookSeasonRepairViewModelTests.swift`와 `CloudFunctionsSeasonImportRepositoryTests.swift`.
- review 이미지 로더: `OutPickTests/LookbookRemotePreviewImageLoaderTests.swift`에서 동일 URL 동시 load 병합과 prefetch URL 중복 제거/동시성 상한을 검증한다.
- 2026-07-23 Phase 4에서 Functions 53/53와 lint/build, iOS targeted 6/6와 iPhone 17 Pro Max Simulator build가 통과했다. 실제 Firebase/Cloud Tasks 통합과 관리자 화면 수동 QA는 미수행이다.
- Phase 5 cleanup path contract는 `functions/src/lookbook/import/evidenceCleanup.test.ts`에서 검증한다. Phase 5 전체 Functions 55/55와 lint/build가 통과했으며 실제 Storage delete smoke QA는 배포 전까지 보류한다.
- Phase 6 전체는 worker 57/57, fixture 4/4, Functions 57/57, iOS 관련 targeted 9/9가 통과했다. 2026-07-23 운영 배포 후 YOUTH repair preview `keep 1/add 45/reorder 0/remove 0`을 같은 season에 적용해 post `1 → 46`, 기존 `post_0000` 보존, post asset `ready` 46과 job asset failed 0을 확인했다.
- 2026-07-23 Phase 7 전 review UI 보완은 Functions 57/57와 lint/build, remote preview loader·review/repair ViewModel·Cloud Functions repository targeted 11/11, iPhone 17 Pro Max Simulator build/run을 통과했다. repair 2열 grid의 실제 운영 데이터 스크롤 시각 QA는 남아 있다.
- 같은 날 repair no-change terminal 보완은 Worker 59/59와 fixture 4/4, Functions 58/58와 lint/build, iOS repair 상태/ViewModel/repository/loader targeted 10/10 및 Simulator build/run을 통과했다. worker `lookbook-import-worker-00017-stx`와 Firebase Functions 운영 재배포 후 Ready/traffic 100%, 큐 RUNNING, 새 revision recent ERROR 0건과 repair callable ACTIVE를 확인했다. 실제 운영 no-change 비교 smoke는 데이터 mutation을 수반하므로 별도 실행 대상으로 남겼다.
- Phase 7 adapter registry는 Cafe24 positive, Generic/비-Cafe24 negative, domain fixture/host gate, 전체 adapter version cache invalidation을 자동 검증한다.
- Phase 8은 Worker lint/build와 65/65, fixture corpus 4/4·diff 0건, Functions lint/build와 58/58, iOS targeted 14/14 및 Simulator build/run을 통과했다. 운영 worker `lookbook-import-worker-00018-zwl` 배포 뒤 OUTSTANDING static 12 → rendered 44, YOUTH read-only live URL static 1 → source 46, HATCHINGROOM 후보 17을 확인했고 queue pending 0건과 새 revision ERROR 0건이었다.
- Phase 8 종료 후 YOUTH 신규 등록 회귀 보완은 `collection_detail.html`과 분리된 이미지/제목 anchor 최소 fixture를 추가했다. extractor `1.2.1`, Worker lint/build와 65/65, fixture corpus 5/5·diff 0건이 통과했고 2026-07-23 현재 YOUTH 공개 목록 HTML의 정적 후보가 `0 → 20`으로 복구됨을 읽기 전용으로 확인했다.
- 같은 보완 worker를 `lookbook-import-worker-00019-ftd`로 운영 배포해 Ready/traffic 100%, startup probe·port listen, ERROR 0건과 queue task 0건을 확인했다. 별도 health task는 Cloud Run 인증 계층 404로 container request log에 도달하지 않아 모두 삭제했지만, 이후 사용자 수동 QA에서 실제 앱의 YOUTH 시즌 추출 목록이 정상 표시돼 callable→worker→후보 저장·표시 smoke를 완료했다.
- extraction review 수량 기준 보완은 예상 수 일치/불일치/미확인, 첫 signature 자동 진행, raw 후보 감소 evidence-only, content hash 차단을 Worker 66/66과 fixture 5/5로 검증했다. iOS는 미달 승인 차단·예상 수 prefill·미확인 수동 승인/부족 보고·무결성 차단과 repository contract targeted 10/10, Simulator build/run을 통과했다.
- 같은 worker를 `lookbook-import-worker-00021-ghs`로 운영 배포해 Ready/traffic 100%, startup probe·port 8080 listen, recent ERROR 0건, queue RUNNING/pending 0건을 확인했다. rollback은 `lookbook-import-worker-00019-ftd`다.
- expected-count 활성 grid scope 후 extractor `1.2.3` Worker 67/67·lint/build·fixture 5/5와 실제 저장 YOUTH HTML `46/49` evidence를 확인했다. 운영 `lookbook-import-worker-00022-5gn`은 Ready/Active·traffic 100%, recent ERROR 0건, queue RUNNING/pending 0건이며 rollback은 `00021-ghs`다.

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

- Chat route lifecycle hardening tests: `OutPickTests/ChatNavigationControllerTests.swift`, `ChatNavigationStackPolicyTests.swift`, `ChatOpenRoomRequestStateTests.swift`, `ChatOpenRoomRequestRegistryTests.swift`, `ChatRoomRouteLifecycleStateTests.swift`
  - Chat navigation은 root edge-pop 차단, 일반 push 허용, 화면 정책에 따른 방 생성형 push 차단, iOS 26 content-pop 유지 계약을 검증한다.
  - 같은 stack의 기존 Chat route 교체와 non-Chat prefix 보존, top same-room no-op를 검증한다.
  - stack별 요청 격리, same-room 실제 Task 공유, same-stack latest-wins, stale 성공·실패 무시와 실패 후 재시도를 검증한다.
  - terminal route가 `didAppear`로 부활하지 않고 transient binding 복구 대상에서 제외되는 lifecycle 계약을 검증한다.
  - 2026-07-22 D19 방 생성 차단 보강 뒤 Chat navigation 4개와 관련 navigation/route/lifecycle/request 묶음 24개, iOS 26.2 Simulator build/install/launch가 통과했다. 방 생성 swipe 차단과 Back 확인창도 Simulator 수동 QA를 통과했으며 이 시점에는 실제 Chat·실기기 swipe가 남아 있었다.
  - 같은 날 실제 Chat·검색 실기기 swipe 취소/완료로 Phase 6을 종료했다. Phase 7 dead transition 네 파일 제거 뒤 정적 참조 0건, 같은 24개 회귀와 generic Simulator build가 통과했다.
  - Phase 7 삭제 후 Chat push/pop과 Profile modal 열기/닫기 수동 smoke QA도 통과했다.
  - Phase 7B Profile modal edge-swipe는 단순 touch wiring이라 별도 UI unit test를 추가하지 않았다. 기존 24개 회귀와 generic Simulator build, iOS 26.2 Simulator 설치·실행이 통과했고 사용자가 짧은 swipe 유지, 임계값 충족 닫기, X 버튼·avatar tap을 수동 확인해 Phase 7B를 종료했다.
  - Phase 8 Chat gesture는 UIKit touch arbitration 전용 추상화를 추가하지 않고 기존 `ChatRoomViewModelMessageActionTests`, `ChatMessageActionPolicyTests`를 회귀 대상으로 유지한다. 제거 symbol 참조 0건, `git diff --check`, generic Simulator build가 통과했고 기존 테스트 실행은 보류했다. iPhone 17 Pro Max iOS 26.2에서 keyboard/attachment/message menu background dismiss, input/attachment control 보존, message/announcement long press, settings dim, Lookbook과 retry cell tap이 통과했다. 마지막 media/profile cell tap도 사용자의 실제 Simulator 확인으로 통과해 Phase 8 수동 QA를 완료했다.
  - Phase 9 최종 회귀에서 위 5개 suite 24/24를 재실행했다. 이어 `ChatRoomSessionActorTests`, `RealtimeChatIngressOrderingTests`, `RealtimeSocketRoomSummaryOwnershipTests`, `RealtimeSocketListenerBinderTests`, `ChatReadStateStoreTests`, `ChatRoomReadStateStoreTests`, `ChatUnreadCatchUpStateTests`, `ChatMessageWindowStoreTests`, `ChatRoomViewModelMessageActionTests` 86/86과 최신 Debug build/install/launch가 통과했다.
  - 실제 Simulator에서 검색 prefix 보존, RoomCreate 취소 흐름, Lookbook 공유 완료 후 명시적 Chat 이동, 참여중/Lookbook stack 복원을 확인했다. 실제 Firebase 완료 순서 역전은 fetch가 빨라 수동 재현하지 않았고 request state/registry 자동 테스트를 최종 판정 근거로 사용한다.

### Chat route 테스트 파일 지도

| 테스트 파일 | 고정하는 계약 |
| --- | --- |
| `OutPickTests/ChatNavigationControllerTests.swift` | root 차단, push 허용, 화면별 opt-out과 iOS 26 content-pop 유지 |
| `OutPickTests/ChatNavigationStackPolicyTests.swift` | non-Chat prefix 보존, 기존 Chat 제거, same-room no-op |
| `OutPickTests/ChatOpenRoomRequestStateTests.swift` | stack별 token/snapshot, supersede와 stale completion 판정 |
| `OutPickTests/ChatOpenRoomRequestRegistryTests.swift` | 실제 Task coalesce, 오류 공유, retry cleanup과 same-stack latest-wins |
| `OutPickTests/ChatRoomRouteLifecycleStateTests.swift` | transient cover, 취소/완료 pop, dismiss/replacement 단일 finish와 terminal 비가역 |

Chat gesture 자체는 UIKit touch delivery를 위한 별도 추상화를 만들지 않았으므로 전용 unit test가 없다. gesture wiring은 Simulator/실기기 수동 QA로, gesture 이후 message/read/realtime 상태는 Phase 9의 86개 영향 범위 테스트로 검증한다.

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
