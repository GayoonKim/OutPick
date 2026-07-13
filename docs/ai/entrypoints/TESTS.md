# Test Entrypoints

## 공통

- 단위 테스트: `OutPickTests`
- UI 테스트: `OutPickUITests`
- 앱 빌드 기본 검증:

```bash
xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build
```

## Lookbook

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

- Functions package: `functions/package.json`
- Functions source: `functions/src`
- Lookbook deletion purge lease policy: `functions/src/lookbookDeletionPurgeLease.ts`
- Lookbook deletion purge lease tests: `functions/src/lookbookDeletionPurgeLease.test.ts`
- Lookbook deletion purge drain orchestration: `functions/src/lookbookDeletionPurgeDrain.ts`
- Lookbook deletion purge drain tests: `functions/src/lookbookDeletionPurgeDrain.test.ts`
- `functions/package.json`의 `npm test`는 Functions build 후 `lib/*.test.js`를 모두 실행한다.
- 실행: `cd functions && npm test`
- purge drain 핵심 시나리오: 20개 초과 page 반복, 서로 다른 브랜드 최대 3개, 같은 브랜드 순차, 부모 target 우선, 실패/lease skip 후 계속 처리, 7분 cutoff.
- 운영 통합 결과와 남은 관찰 항목: `docs/ai/tasks/lookbook-deletion-purge-drain/progress.md`, `qa-checklist.md`.
- Functions workflow: `.codex/skills/firebase-functions-workflow/SKILL.md`

## Chat / Realtime

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
