# Active Task

## 현재 작업

- 작업명: chat-view-controller-layering
- 진행 문서:
  - `docs/ai/tasks/chat-view-controller-layering/plan.md`
  - `docs/ai/tasks/chat-view-controller-layering/progress.md`
  - `docs/ai/tasks/chat-view-controller-layering/decisions.md`

## 현재 단계

- Phase 6 보강: 읽음 상태 공유 Store/stream 전환 구현, targeted unit test, 앱 빌드/실행 검증 완료.
- `lookbook-chat-share` MVP 완료 후속 작업인 `ChatViewController.swift` 레이어 분리를 독립 task로 승격했다.
- 현재 목표는 `ChatViewController`의 메시지 전송, 소켓 세션, 미디어 처리, 메뉴/action policy, 메시지 window/diffable 책임을 단계적으로 분리하는 것이다.
- 텍스트 메시지 생성과 socket 전송 호출은 `ChatRoomMessageUseCase`와 `ChatMessageSendingRepositoryProtocol` 경계로 이동했다.
- 실시간 수신 stream open은 `ChatRoomRealtimeUseCase`와 `ChatRoomRealtimeRepositoryProtocol` 경계로 이동했고, session close/cancel은 `ChatRoomRealtimeSubscription`이 소유한다.
- 메시지 롱프레스 메뉴 선택 이벤트는 `ChatMessageAction`으로 분리했고, delete/announce 서버 상태 변경 액션은 `ChatRoomViewModel.performMessageServerAction` 경계로 이동했다.
- 메시지 삭제 시 삭제 대상이 마지막 메시지이면 참여중인 목록/오픈채팅 목록에도 "삭제된 메시지입니다."가 반영되도록 room summary와 preview 렌더링을 보정했다.
- 다음 phase부터 iOS 빌드/테스트/실행 검증은 가능한 경우 Build iOS Apps 플러그인의 `xcodebuildmcp`를 우선 사용한다.
- 메시지 list item은 `ChatMessageListItem`으로 승격했고, window/list item/reconfigure 계산은 `ChatMessageWindowStore`가 소유한다.
- pending image upload 상태/task/retry payload는 `ChatPendingMediaUploadStore`가 소유한다.
- pending preview attachment 생성, 이미지 Storage 업로드, 비디오 Storage 업로드, thumbnail cache, socket media broadcast는 `ChatMediaUploadUseCase`와 `ChatMediaMessageSendingRepositoryProtocol` 경계로 이동했다.
- `ChatMediaManaging.uploadCompressedVideoAndBroadcast` fatalError 계약은 제거했다.
- Chat Store 파일은 `OutPick/Features/Chat/Stores/` 폴더에 모았다.
- 읽음 seq 후보/final/flush 상태 계산은 `ChatReadStateStore`가 소유한다.
- 읽음 seq debounce와 persist orchestration은 `ChatRoomViewModel`, near-bottom 판정과 app lifecycle observer는 `ChatViewController`에 유지한다.
- roomID별 read/latest snapshot과 invalidation stream은 `ChatRoomReadStateStore`가 소유한다.
- 참여중인 목록 unread 갱신은 `NotificationCenter` 대신 `ChatRoomReadStateStore` stream을 구독한다.
- Phase 6 보강 수동 QA까지 정상 동작 확인됐다.

## 핵심 원칙

- 파일 분할만으로 완료하지 않는다. 책임 소유권을 ViewModel, UseCase, Repository, Service, Coordinator 경계로 이동한다.
- 기존 MVVM-C + Repository + UseCase + DI 흐름을 우선 따른다.
- `ChatViewController`는 UIKit 화면 조립, 사용자 이벤트 전달, 렌더링 반영에 집중한다.
- Socket/Firebase/GRDB/Storage 직접 접근은 ViewController 밖으로 이동한다.
- 룩북 공유 카드 렌더링은 계속 `sharedContent` snapshot만 사용하고 룩북 원본 Repository를 조회하지 않는다.
- 큰 회귀 위험이 있는 이미지/비디오 업로드 분리는 후반 phase로 둔다.
- iOS 검증은 `xcodebuildmcp.session_show_defaults`로 기본값을 먼저 확인한 뒤 `build_run_sim`, `test_sim`, `launch_app_sim`, `screenshot`을 우선 사용한다.

## 다음 작업 후보

- Phase 7: 채팅 화면 라우팅과 Coordinator 경계 정리.
  - 프로필 상세 이동.
  - 룩북 공유 카드 상세 이동.
  - 방 설정 진입/복귀.
  - 방 나가기/닫힘 후 목록 복귀.
  - `ChatRoomRouting` 확장과 `AppContentRouting` 유지 범위 논의.

## 압축 후 읽는 순서

1. `HANDOFF.md`
2. `docs/ai/tasks/active.md`
3. `docs/ai/tasks/chat-view-controller-layering/plan.md`
4. `docs/ai/tasks/chat-view-controller-layering/progress.md`
5. `docs/ai/tasks/chat-view-controller-layering/decisions.md`
6. `docs/ai/CODE_ARCHITECTURE.md`
7. `docs/ai/SCREEN_SPEC.md`
8. `docs/ai/FLOW.md`
9. `docs/ai/tasks/lookbook-chat-share/progress.md`

## 이전 작업 참고

- `lookbook-chat-share` MVP는 `docs/ai/tasks/lookbook-chat-share/progress.md` 기준 완료 상태다.
- 해당 작업의 후속 후보였던 `ChatViewController.swift` 레이어 분리를 현재 active task로 가져왔다.
- 기존 공유 기능의 원칙은 유지한다.
  - 채팅은 채팅답게 빠르게, 룩북은 들어갔을 때 정확하게.
  - 채팅방 공유 카드는 snapshot만 렌더링한다.
  - 원본 최신성은 카드 탭 후 상세 화면에서 확인한다.
