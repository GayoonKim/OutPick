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

## Lookbook

- iOS Cloud Functions 계약 테스트: `OutPickTests/CloudFunctions/`
  - 공통 decoder와 transport spy, Auth/Admin capability, Brand/Request, Engagement/Comment, Import/Deletion의 사용 callable 38개를 검증한다.
  - 실제 Firebase 서버를 호출하지 않고 function name, payload, response mapping과 오류 보존을 고정한다.

- Lookbook interaction/store tests: `OutPickTests/LookbookInteractionStoreTests.swift`, `OutPickTests/LookbookDebugFailureInjectionStoreTests.swift`
- Lookbook detail tests: `OutPickTests/PostDetailScreenViewModelTests.swift`, `OutPickTests/SeasonDetailViewModelTests.swift`
- 좋아요 탭 tests: `OutPickTests/LikedViewModelTests.swift`, `OutPickTests/LoadLikedSeasonsUseCaseTests.swift`
- 삭제 요청 관리 pagination/retry tests: `OutPickTests/AdminLookbookDeletionManagementViewModelTests.swift`
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

- iOS Socket listener 안정화 test: `OutPickTests/RealtimeSocketListenerBinderTests.swift`
  - client event 3개와 named event 5개의 최초 1회 등록, 같은 binder 재호출 무효, 반복 connect callback 중 등록 수 불변, 새 Socket/binder 독립 등록과 payload 전달을 검증한다.
  - 실행: `xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'platform=iOS Simulator,id={simulator-id}' -only-testing:OutPickTests/RealtimeSocketListenerBinderTests test`.
  - 실제 reconnect gate는 cold launch 5회와 background/foreground 5회, room rejoin/text 중복 부재와 credential raw log 부재를 확인한다. 상세 절차는 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-ios-socket-stabilization.md`에 있다.

- Phase 5 Socket 테스트 계획: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-5-socket-tests.md`
  - `Socket/test/`에서 application/architecture, auth, room/message/media handler와 service, lifecycle/runtime/state 계약을 검증한다.
  - `Socket/scripts/run-tests.mjs`는 모든 `*.test.js`를 재귀 발견하며 0개 test를 실패 처리한다.
  - 실행: `npm --prefix Socket run check`, `npm --prefix Socket test`.
  - 2026-07-14 syntax check와 43개 `node:test`, ADC 기반 room preload/health/graceful shutdown local smoke가 통과했다. Cloud Run/iOS 실제 송수신 smoke는 미수행이다.

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
