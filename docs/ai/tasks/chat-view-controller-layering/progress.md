# ChatViewController Layering Progress

## 현재 상태

- 상태: Phase 6 보강으로 읽음 상태 공유 Store/stream 전환 구현, targeted unit test, 앱 빌드/실행 검증 완료.
- `lookbook-chat-share` MVP 완료 후속 작업인 `ChatViewController.swift` 레이어 분리를 독립 task로 승격했다.
- 첫 코드 phase로 텍스트 메시지 생성/전송 책임을 `ChatViewController` 밖으로 이동했다.
- 두 번째 코드 phase로 실시간 수신 socket session/task/close 경계를 Repository/UseCase/Subscription으로 이동했다.
- 세 번째 코드 phase로 메시지 롱프레스 메뉴 선택 이벤트와 서버 상태 변경 액션 실행 경계를 분리했다.
- 삭제 대상이 방의 마지막 메시지인 경우 참여중인 목록과 오픈채팅 목록에 삭제 표시가 반영되도록 room summary와 preview 렌더링 경로를 보정했다.
- 다음 phase부터 iOS 빌드/테스트/시뮬레이터 실행 검증은 가능한 경우 Build iOS Apps 플러그인의 `xcodebuildmcp`를 우선 사용하기로 했다.
- 네 번째 코드 phase로 메시지 window/list item 상태 계산을 `ChatMessageWindowStore`로 이동했다.
- 다섯 번째 코드 phase로 pending image state/task/retry payload, preview attachment 생성, 이미지/비디오 Storage 업로드와 socket media broadcast 경계를 `ChatViewController` 밖으로 이동했다.
- 여섯 번째 코드 phase로 읽음 seq 후보/final/flush 상태 계산을 `ChatReadStateStore`로 이동했다.
- Phase 6 보강으로 참여중인 목록과 현재 채팅방이 공유하는 `ChatRoomReadStateStore`를 추가하고, `NotificationCenter` 기반 unread 갱신을 제거했다.
- Phase 6 수동 QA 완료: 참여중인 목록 unread 갱신과 현재 채팅방 읽음 상태 공유가 정상 동작하는 것을 사용자 확인했다.
- 다음 phase는 화면 이동/라우팅 책임을 Coordinator 경계로 정리하는 Phase 7로 잡는다.

## Phase 0 완료 기록

- 새 task 문서 생성:
  - `docs/ai/tasks/chat-view-controller-layering/plan.md`
  - `docs/ai/tasks/chat-view-controller-layering/progress.md`
  - `docs/ai/tasks/chat-view-controller-layering/decisions.md`
- `docs/ai/tasks/active.md`를 새 task 기준으로 갱신했다.
- 리팩토링 phase를 다음 순서로 정리했다.
  - Phase 1: 텍스트 메시지 전송 경계 분리.
  - Phase 2: 실시간 소켓 세션 관찰 분리.
  - Phase 3: 메시지 액션/menu 분리.
  - Phase 4: 메시지 window와 diffable helper 분리.
  - Phase 5: 이미지/비디오 pending upload 분리.
  - Phase 6: 읽음 seq와 lifecycle 정리.

## 완료한 결정

- 첫 코드 phase는 텍스트 메시지 전송 경계 분리를 추천안으로 둔다.
- 미디어 업로드 분리는 회귀 위험이 높으므로 초반 phase에서 제외한다.
- `ChatViewController` 파일 분할만으로 끝내지 않고, UseCase/Repository/Service/Coordinator 경계로 책임을 이동한다.
- Phase 0은 문서 작업이므로 자동 테스트와 빌드를 실행하지 않는다.
- optimistic message는 UseCase가 생성하고, ViewController가 화면에 먼저 반영한 뒤 ViewModel을 통해 prepared message를 전송한다.
- 실시간 stream 소유권은 Repository/UseCase가 stream을 제공하고 `ChatRoomRealtimeSubscription`이 task와 close를 소유하는 방식으로 정리한다.
- 메시지 액션 실행 경계는 B안을 채택했다.
  - delete/announce처럼 서버 상태를 바꾸는 액션은 ViewModel/UseCase 경계로 이동한다.
  - reply/copy/report toast처럼 로컬 UI feedback 성격의 액션은 ViewController에 남긴다.
  - report는 기존 toast만 유지하고 실제 신고 저장/서버 처리는 후속 기능 phase에서 별도 설계한다.
- iOS 검증 도구는 Build iOS Apps 플러그인의 `xcodebuildmcp`를 우선 사용한다.
  - 첫 build/run/test 전 `session_show_defaults`로 기본값을 확인한다.
  - 빌드/실행은 `build_run_sim`, 테스트는 `test_sim`, 앱 재실행은 `launch_app_sim`, 시각 확인은 `screenshot`을 우선 검토한다.
  - 플러그인 미지원 특수 검증에는 shell `xcodebuild`를 fallback으로 사용할 수 있다.
- Phase 4 메시지 list item 타입 위치는 B안을 채택했다.
  - `ChatViewController.Item` 내부 enum을 유지하지 않고 `ChatMessageListItem`으로 승격했다.
  - 메시지 window 상태 계산은 `ChatMessageWindowStore`가 소유한다.
  - pending image upload 처리는 Phase 5 범위로 남기고, Phase 4에서는 store의 메시지 상태 갱신만 연결했다.
- Phase 5 이미지/비디오 업로드 분리 범위는 추천안을 채택했다.
  - 이미지와 비디오 업로드 경계는 `ChatMediaUploadUseCase`로 묶는다.
  - pending image 상태/task/retry payload는 `ChatPendingMediaUploadStore`가 소유한다.
  - socket media broadcast는 `ChatMediaMessageSendingRepositoryProtocol` 뒤로 숨긴다.
  - 비디오 pending cell/retry UX 통합은 이번 phase에서 하지 않고 기존 실패 메시지 흐름을 유지한다.
- Phase 6 읽음 seq/lifecycle 정리 범위는 추천안을 채택했다.
  - 읽음 seq 후보 계산, final seq 계산, pending/queued/persisted 상태 전이는 `ChatReadStateStore`가 소유한다.
  - debounce task와 실제 persist orchestration은 `ChatRoomViewModel`에 유지한다.
  - app lifecycle observer와 near-bottom UI 판정은 `ChatViewController`에 유지한다.
  - Store 파일이 2개 이상 생겼으므로 `OutPick/Features/Chat/Stores/` 폴더를 만들고 Chat Store 파일을 모았다.
- Phase 6 보강 읽음 상태 공유 구조는 추천안을 채택했다.
  - 단일 방 flush 상태 머신인 `ChatReadStateStore`는 유지한다.
  - roomID별 latest/read snapshot과 invalidation stream은 `ChatRoomReadStateStore`가 소유한다.
  - `JoinedRoomsViewModel`은 `NotificationCenter` 대신 `ChatRoomReadStateStore`의 `AsyncStream`을 구독한다.
  - bootstrap/pull-to-refresh 성격의 unread 계산은 서버 snapshot으로 Store를 seed하고, 런타임 중에는 Store snapshot으로 즉시 계산한다.

## Phase 1 구현 기록

- `ChatMessageSendingRepositoryProtocol`과 `SocketChatMessageSendingRepository`를 추가했다.
- `SocketIOManager.sendMessage(_:_:)`는 `ChatTextMessageSocketSending` protocol 뒤로 감쌌다.
- `ChatRoomMessageUseCase`에 텍스트 메시지 생성과 prepared message 전송 경계를 추가했다.
  - `makeTextMessage(text:replyPreview:room:)`
  - `sendPreparedMessage(_:room:)`
- `ChatRoomMessageUseCase`는 current user snapshot, message ID, date provider를 주입받아 테스트 가능하게 만들었다.
- `ChatRoomViewModel`은 ViewController가 사용할 좁은 API를 제공한다.
  - `makeOutgoingTextMessage(text:replyPreview:)`
  - `sendPreparedMessage(_:)`
- `ChatContainer`는 socket sending repository를 생성해 `ChatRoomMessageUseCase`에 주입한다.
- `ChatViewController.handleSendButtonTap`은 더 이상 `LoginManager.shared`와 `SocketIOManager.shared.sendMessage`를 직접 호출하지 않는다.
- optimistic render 순서는 유지했다.
  - ViewModel/UseCase가 outgoing message 생성.
  - ViewController가 먼저 `addMessages(..., updateType: .newer)`로 표시.
  - 이후 ViewModel을 통해 prepared message 전송.
- `ChatRoomMessageUseCaseTests`를 추가했다.
  - trim된 텍스트와 injected sender snapshot으로 optimistic message를 생성하는지 검증.
  - blank text 또는 roomID 누락 시 메시지를 만들지 않는지 검증.
  - prepared message 전송이 repository로 위임되는지 검증.

## Phase 2 구현 기록

- `ChatRoomRealtimeRepositoryProtocol`과 `SocketChatRoomRealtimeRepository`를 추가했다.
- `SocketIOManager.openRoomSession(for:)`는 `ChatRoomRealtimeSocketOpening` protocol 뒤로 감쌌다.
- `ChatRoomRealtimeUseCase`를 추가해 ViewModel이 socket 구현을 직접 알지 않게 했다.
- `ChatRoomRealtimeSubscription`을 추가했다.
  - message stream task를 소유한다.
  - opened session close/cancel 경계를 소유한다.
  - stream 종료 시 subscription identity로 현재 구독인지 확인해 오래된 stream이 새 구독을 지우지 않게 한다.
- `ChatRoomViewModel`은 `openMessageStream(roomID:)`만 제공한다.
- `ChatContainer`는 realtime use case를 생성해 `ChatRoomViewModel`에 주입한다.
- `ChatViewController.startRoomMessageStream`은 더 이상 `SocketIOManager.shared.openRoomSession`을 직접 호출하지 않는다.
- `ChatViewController`에서 제거한 직접 소유 상태:
  - `roomMessageTask`
  - `roomSession`
  - `activeRealtimeRoomID`
  - `activeRealtimeStreamToken`
- `ChatRoomRealtimeUseCaseTests`를 추가했다.
  - fake realtime repository가 roomID를 받는지 검증.
  - repository가 제공한 `AsyncStream<ChatMessage>`가 use case 경계 밖으로 전달되는지 검증.

## Phase 3 구현 기록

- `ChatMessageAction`과 `ChatMessageServerAction` 값을 추가했다.
- `ChatMessageActionPolicy`에 `allows(_:)`를 추가해 메뉴 선택 이벤트 방어선을 순수 정책 객체에 유지했다.
- `ChatCustomPopUpMenu`는 개별 action closure 다섯 개 대신 `onActionSelected` 하나로 선택된 action만 전달한다.
- `ChatRoomViewModel`에 메시지 액션 경계를 추가했다.
  - `messageActionPolicy(for:currentUserID:)`
  - `performMessageServerAction(_:for:)`
- `ChatViewController`는 롱프레스 메뉴 표시, confirm/toast/clipboard/reply UI feedback을 담당한다.
- `ChatViewController`에서 `messageManager.deleteMessage` 직접 호출 fallback을 제거했다.
- `OutPickTests/ChatRoomViewModelMessageActionTests.swift`를 추가했다.
  - 방 생성자 기준 action policy 위임 검증.
  - delete action이 message use case로 위임되는지 검증.
  - announce action이 lifecycle use case로 위임되는지 검증.
- 사용자 수동 QA 피드백 기준 답장은 동작하나 reply preview separator 대비가 약해 `ChatMessageCell.replyPreviewSeparator` 색을 `borderSubtle`에서 `iconSecondary.withAlphaComponent(0.65)`로 조정했다.
- 삭제한 메시지가 목록에서 원문으로 남는 문제를 수정했다.
  - `ChatRoomMessageUseCase.deleteMessage`가 삭제 처리 뒤 마지막 메시지 요약 갱신 경계를 호출한다.
  - `FirebaseChatRoomRepository.updateDeletedLastMessageSummaryIfCurrent`는 Firestore transaction에서 room의 현재 `seq` 또는 `lastMessageSeq`가 삭제 대상 메시지 `seq`와 같을 때만 `lastMessage`를 "삭제된 메시지입니다."로 갱신한다.
  - `lastMessageAt`은 갱신하지 않아 삭제 액션만으로 방 정렬이 최신으로 끌려오지 않게 했다.
  - `RoomListCollectionViewCell.MessagePreviewView`는 `isDeleted`를 본문/첨부보다 먼저 확인해 오픈채팅 메시지 preview 배열도 삭제 표시를 우선 렌더링한다.
- `ChatRoomMessageUseCaseTests`에 삭제 메시지 요약 갱신 테스트를 추가했다.
  - `seq`가 있는 삭제 메시지는 summary updater로 위임되는지 검증.
  - `seq`가 없으면 stale aggregate 갱신을 시도하지 않는지 검증.

## Phase 4 구현 기록

- `ChatMessageListItem`을 추가해 collection view list item 타입을 `ChatViewController` 내부 enum에서 승격했다.
  - `.message(ChatMessage)`
  - `.dateSeparator(Date)`
  - `.readMarker`
- `ChatMessageWindowStore`를 추가했다.
  - visible window item 배열을 소유한다.
  - 메시지 ID 기준 최신 메시지 map을 소유한다.
  - 중복 메시지 제거, 날짜 구분선 삽입, read marker 삽입, older/newer virtualization, reload/reconfigure 대상 계산을 담당한다.
- `ChatViewController`는 `messageMap`, `lastMessageDate`, read marker/window 계산을 직접 소유하지 않는다.
- `ChatViewController.addMessages`는 store mutation 결과를 diffable snapshot에 반영하는 역할로 축소했다.
- 삭제 listener, 프로필 동기화, pending image upload 실패 상태, 미디어 프리페치, 이미지 뷰어, 롱프레스 메뉴는 store에서 최신 메시지를 조회하도록 연결했다.
- pagination anchor는 snapshot scan 대신 `ChatMessageWindowStore.firstMessageID()`와 `lastMessageID()`를 사용한다.
- `OutPickTests/ChatMessageWindowStoreTests.swift`를 추가했다.
  - 초기 window의 날짜선/read marker 삽입 검증.
  - 입력 중복 제거와 기존 메시지 reconfigure 검증.
  - newer 메시지가 unread boundary를 넘을 때 read marker 삽입 검증.
  - newer virtualization 시 오래된 메시지와 message map pruning 검증.
  - reload 시 visible message와 reconfigure 대상 갱신 검증.

## Phase 5 구현 기록

- `ChatPendingMediaUploadStore`를 추가했다.
  - pending image upload의 `uploading/failed` 상태를 소유한다.
  - messageID별 원본 image pair, retry payload, upload task 중복 방지를 관리한다.
  - retry payload는 failed 상태이고 active task가 없을 때만 반환한다.
- `ChatMediaUploadUseCase`를 추가했다.
  - pending image preview attachment 파일 생성과 pending message 생성을 담당한다.
  - 이미지 Storage 업로드, 성공 시 원본 temp cleanup, 실패 시 thumbnail cache 저장 경계를 제공한다.
  - 비디오 Storage 업로드, thumbnail Storage 업로드, thumbnail cache 저장, `VideoMetaPayload` 생성을 담당한다.
  - 서버 전송 성공/실패 media broadcast는 repository 경계로 위임한다.
- `ChatMediaMessageSendingRepositoryProtocol`과 `SocketChatMediaMessageSendingRepository`를 추가했다.
  - `SocketIOManager.sendImages`
  - `SocketIOManager.sendVideo`
  - `SocketIOManager.sendFailedVideos`
  위 호출을 ViewController 밖으로 숨겼다.
- `ChatViewController`는 pending image store/usecase를 사용한다.
  - pending message 화면 삽입.
  - upload progress overlay 반영.
  - retry tap 이벤트 전달.
  - HUD/alert 표시.
  역할만 남겼다.
- `ChatViewControllerExtension.uploadPendingImageMessage`는 Firebase Storage와 SocketIOManager를 직접 호출하지 않는다.
- `ChatViewControllerExtension.uploadPreparedVideoAndBroadcast`는 기존 이름과 호출 흐름은 유지하되, 내부 구현을 `ChatMediaUploadUseCase` 호출로 축소했다.
- `ChatMediaManaging.uploadCompressedVideoAndBroadcast` 요구사항과 `ChatMediaManager`의 fatalError 기본 구현을 제거했다.
- `OutPickTests/ChatPendingMediaUploadStoreTests.swift`를 추가했다.
  - stage 후 초기 uploading 상태와 실패 후 retry payload 반환 검증.
  - active task 중복 시작 방지와 task finish 후 재시작 가능 검증.
  - complete 후 state/payload 제거 검증.
- `OutPickTests/ChatMediaUploadUseCaseTests.swift`를 추가했다.
  - pending image message와 local preview attachment 생성 검증.
  - 이미지 업로드 성공 시 원본 cleanup과 socket repository 위임 검증.
  - 실패 image thumbnail cache 저장 검증.
  - 비디오 업로드 payload/storage path/thumbnail upload/cache/send 위임 검증.
  - local prepared video 실패 메시지 repository 위임 검증.

## Phase 6 구현 기록

- `OutPick/Features/Chat/Stores/` 폴더를 추가하고 Chat Store 파일을 모았다.
  - `ChatMessageWindowStore`
  - `ChatPendingMediaUploadStore`
  - `ChatReadStateStore`
- `ChatReadStateStore`를 추가했다.
  - pending/queued/persisted last read seq 상태를 소유한다.
  - near-bottom 조건을 반영한 next candidate 계산을 담당한다.
  - 화면 이탈/종료 시 사용할 final seq max 계산을 담당한다.
  - flush 대상 seq와 flush 완료 후 상태 전이를 담당한다.
- `ChatRoomViewModel`은 읽음 seq 숫자 필드 세 개를 직접 들지 않고 `ChatReadStateStore`에 위임한다.
- `ChatRoomViewModel`에 남긴 책임:
  - debounce task 예약/취소.
  - `ChatRoomLifecycleUseCase.updateLastReadSeq` 호출.
  - 초기 메시지 동기화 시 read store reset.
- `ChatViewController`에 유지한 책임:
  - near-bottom UI state 판정.
  - app lifecycle observer 등록.
  - background/terminate/화면 이탈 시 ViewModel flush 호출.
- `OutPickTests/ChatReadStateStoreTests.swift`를 추가했다.
  - near-bottom 조건과 skip 조건 검증.
  - queued/pending seq monotonic update 검증.
  - flush 완료 후 persisted/pending 상태 전이 검증.
  - final seq max 계산 검증.
  - reset 동작 검증.

## Phase 6 보강 구현 기록

- `ChatRoomReadStateStore`를 추가했다.
  - roomID별 `latestSeq`, `lastReadSeq`, `lastMessageSenderID` snapshot을 소유한다.
  - `AsyncStream<ChatRoomReadStateChange>`로 특정 room 또는 전체 room read-state 변경을 발행한다.
  - snapshot이 충분하면 `latestSeq - lastReadSeq` 기준 unread count를 즉시 계산한다.
  - 마지막 메시지 작성자가 현재 사용자면 기존 unread 보정 정책을 유지한다.
- `ChatContainer`가 `ChatRoomReadStateStore` 공유 인스턴스를 생성/보관하고 `JoinedRoomsViewModel`, `ChatRoomViewModel`에 주입한다.
- storyboard fallback을 위해 `ChatDependencyContainer.requireRoomReadStateStore()`를 추가했다.
- `JoinedRoomsViewModel`은 read-state stream을 구독한다.
  - room summary 수신/초기 bootstrap/tail page load 시 latest snapshot을 seed한다.
  - 서버에서 읽어온 read snapshot으로 Store를 seed한다.
  - Store 변경 이벤트를 받으면 가능한 경우 서버 재조회 없이 `state.unreadCounts`를 갱신한다.
- `ChatRoomViewModel`은 shared read-state Store에 런타임 상태를 반영한다.
  - 초기 메시지 sync 시 latest/read boundary를 seed한다.
  - room document update와 실시간 수신 메시지로 latest snapshot을 seed한다.
  - lastReadSeq flush 성공 후 `markReadFlushed(roomID:lastReadSeq:)`를 호출한다.
- `ChatViewController`와 `JoinedRoomsViewController` 사이의 `.chatRoomLastReadSeqDidFlush` `NotificationCenter` 경로를 제거했다.
- `ChatNotifications.swift`를 삭제했다.
- `OutPickTests/ChatRoomReadStateStoreTests.swift`를 추가했다.
  - unread 계산의 현재 사용자 sender 보정 검증.
  - roomID 필터 stream 발행 검증.
  - read seq monotonic update 검증.
- `ChatRoomViewModelMessageActionTests`에 flush 성공 후 shared Store 반영 테스트를 추가했다.

## 아직 구현하지 않은 것

- Phase 7 채팅 화면 라우팅과 Coordinator 경계 정리.

## 미확인 리스크

- 비디오 업로드 실패 후 재시도 UX는 pending image retry와 완전히 같은 UX가 아니다. 실패 시 pending video message 자체를 failed 상태로 표시하지만, 별도 retry payload 통합은 후속 제품 결정이 필요하다.
- 실제 socket disconnected 실패 메시지 표시 동작은 로컬 socket 상태 재현이 필요하다.
- background/terminate 시 실제 unread count 반영과 참여중인 목록 UI 반영은 사용자 수동 QA에서 정상 동작 확인됐다.
- 룩북 공유 MVP 변경분이 아직 working tree에 많이 남아 있어 커밋 정리 시 작업 단위 분리가 필요하다.

## 다음 작업

1. Phase 7 진입 전 라우팅 책임 inventory를 확인한다.
   - 프로필 상세 이동.
   - 룩북 공유 카드 상세 이동.
   - 방 설정 진입/복귀.
   - 방 나가기/닫힘 후 목록 복귀.
2. `ChatRoomRouting` 확장 범위와 `AppContentRouting` 유지 범위를 논의한다.

## 검증 기록

- Phase 0 문서 생성 후 `git diff --check -- docs/ai/tasks/active.md docs/ai/tasks/chat-view-controller-layering/plan.md docs/ai/tasks/chat-view-controller-layering/progress.md docs/ai/tasks/chat-view-controller-layering/decisions.md` 확인 완료.
- Phase 1 후 `git diff --check -- OutPick/Features/Chat/Repositories/ChatMessageSendingRepository.swift OutPick/Features/Chat/Domain/UseCases/ChatRoomMessageUseCase.swift OutPick/Features/Chat/ViewModels/ChatRoomViewModel.swift OutPick/Features/Chat/ChatContainer.swift OutPick/Features/Chat/Controllers/ChatViewController.swift OutPickTests/ChatRoomMessageUseCaseTests.swift` 확인 완료.
- Phase 1 첫 `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing`는 `ChatRoomMessageUseCaseTests` stub의 `Empty()` generic 추론 오류로 실패했다.
- stub cancellable 반환을 `AnyCancellable {}`로 수정했다.
- Phase 1 재검증 `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 통과.
- Phase 2 후 `rg -n "roomMessageTask|roomSession|activeRealtimeRoomID|activeRealtimeStreamToken|SocketIOManager\\.shared\\.openRoomSession|ChatRoomSocketSession" ...` 확인 결과 `ChatViewController`에는 raw socket/session/task/token 참조가 남지 않았다.
- Phase 2 첫 `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing`는 `ChatViewController.deinit`에서 `@MainActor` subscription `stop()`을 직접 호출해 실패했다.
- deinit 백업 정리를 `Task { @MainActor in realtimeSubscription?.stop() }`로 이동했다.
- Phase 2 재검증 `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 통과.
- 사용자 수동 QA 확인 완료.
  - 방 진입 후 실시간 수신 정상.
  - 화면 이탈 후 중복 수신 없음.
  - 기존 채팅 흐름 정상 동작.
- Phase 2 빌드에서 기존 warning이 남아 있다.
  - `ChatViewController.swift`의 `contentEdgeInsets` deprecation warning.
  - `LoadChatRoomParticipantsUseCase` main actor isolation warning.
  - `SocketIOManager.swift`의 unused weak self warning.
  - functions node_modules linker search path warning.
- Phase 3 후 `rg -n "chatCustomMenu\\.onReply|chatCustomMenu\\.onCopy|chatCustomMenu\\.onDelete|chatCustomMenu\\.onReport|chatCustomMenu\\.onAnnounce|messageManager\\.deleteMessage\\(message" ...` 확인 결과 남은 참조 없음.
- Phase 3 후 `git diff --check -- ...` 통과.
- Phase 3 후 `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 통과.
- Phase 3 targeted unit test 실행 통과.
  - `xcodebuild -quiet -scheme OutPick -destination 'id=7544249E-D0EE-4B88-A48F-E384DF84E6A4' -only-testing:OutPickTests/ChatRoomViewModelMessageActionTests test`
  - `ChatRoomViewModelMessageActionTests` 3개 통과.
- Phase 3 사용자 수동 QA:
  - 답장은 정상 동작 확인.
  - 나머지 메시지 액션/menu 흐름도 정상 구현된 것으로 사용자 확인.
  - 답장 메시지 preview separator가 잘 보이지 않는 UI 피드백을 받아 색상 대비 보정.
- 답장 preview separator 보정 후 `git diff --check -- OutPick/Features/Chat/Views/Cell/ChatMessageCell.swift` 통과.
- 답장 preview separator 보정 후 `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 통과.
- 삭제 메시지 목록 요약 보정 후 `git diff --check -- OutPick/Features/Chat/Domain/UseCases/ChatRoomMessageUseCase.swift OutPick/Features/Chat/ChatContainer.swift OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift OutPick/Features/Chat/Views/Cell/RoomListCollectionViewCell.swift OutPickTests/ChatRoomMessageUseCaseTests.swift` 통과.
- 삭제 메시지 목록 요약 보정 후 targeted unit test 실행 통과.
  - `xcodebuild -quiet -scheme OutPick -destination 'id=7544249E-D0EE-4B88-A48F-E384DF84E6A4' -only-testing:OutPickTests/ChatRoomMessageUseCaseTests test`
  - `ChatRoomMessageUseCaseTests` 5개 통과.
- 삭제 메시지 목록 요약 보정 후 `xcodebuild -quiet -scheme OutPick -destination 'generic/platform=iOS Simulator' build-for-testing` 통과.
- Phase 3 검증에서도 기존 warning이 남아 있다.
  - storyboard prototype cell reuse identifier warning.
  - `ChatViewController.swift` 등 기존 `contentEdgeInsets` deprecation warning.
  - `LoadChatRoomParticipantsUseCase` main actor isolation warning.
  - functions node_modules linker search path warning.
- Phase 4 진입 전 `xcodebuildmcp.session_show_defaults` 확인 결과 기본값이 비어 있어 `list_schemes`, `list_sims` 후 `session_set_defaults`로 `OutPick.xcodeproj` / `OutPick` scheme / booted `iPhone 17 Pro Max` simulator를 설정했다.
- Phase 4 첫 `xcodebuildmcp.test_sim -only-testing:OutPickTests/ChatMessageWindowStoreTests`는 `ChatMessageWindowStore.removeOrphanDateSeparators`의 Swift exclusivity 오류로 실패했다.
- `items.removeAll` 클로저 안에서 `self`를 읽지 않도록 calendar/fallback date를 로컬 상수로 분리했다.
- Phase 4 targeted unit test 재실행 통과.
  - `xcodebuildmcp.test_sim` with `-only-testing:OutPickTests/ChatMessageWindowStoreTests`
  - `ChatMessageWindowStoreTests` 5개 통과.
- Phase 4 관련 targeted unit test 실행 통과.
  - `xcodebuildmcp.test_sim` with `-only-testing:OutPickTests/ChatMessageWindowStoreTests`, `-only-testing:OutPickTests/ChatRoomMessageUseCaseTests`, `-only-testing:OutPickTests/ChatRoomViewModelMessageActionTests`
  - 13개 통과.
- Phase 4 앱 빌드/실행 검증 통과.
  - `xcodebuildmcp.build_run_sim`
  - bundle id `GayoonKim.OutPick`, simulator `7544249E-D0EE-4B88-A48F-E384DF84E6A4`.
- Phase 4 검증에서도 기존 warning이 남아 있다.
  - `ChatViewController.swift` 등 기존 `contentEdgeInsets` deprecation warning.
  - `LoadChatRoomParticipantsUseCase` main actor isolation warning.
  - functions node_modules linker search path warning.
- Phase 4 사용자 수동 QA 확인 완료.
  - 스크롤 pagination 정상.
  - 검색 jump 정상.
  - 삭제 메시지 reload 정상.
  - pending image 기존 흐름 정상.
- Phase 5 첫 관련 targeted unit test는 `ChatViewController.deinit`에서 `@MainActor` pending store method를 직접 호출해 실패했다.
- deinit의 pending store task cancel/remove를 self capture 없는 `Task { @MainActor in ... }`로 이동했다.
- Phase 5 두 번째 관련 targeted unit test는 테스트 코드에서 앱 `Attachment` 모델과 UIKit 이름 충돌로 실패했다.
- 테스트에서 `typealias ChatAttachment = OutPick.Attachment`로 앱 모델을 명확히 지정했다.
- Phase 5 관련 targeted unit test 실행 통과.
  - `xcodebuildmcp.test_sim` with `-only-testing:OutPickTests/ChatMediaUploadUseCaseTests`, `-only-testing:OutPickTests/ChatPendingMediaUploadStoreTests`, `-only-testing:OutPickTests/ChatMessageWindowStoreTests`, `-only-testing:OutPickTests/ChatRoomMessageUseCaseTests`, `-only-testing:OutPickTests/ChatRoomViewModelMessageActionTests`
  - 21개 통과.
- Phase 5 앱 빌드/실행 검증 통과.
  - `xcodebuildmcp.build_run_sim`
  - bundle id `GayoonKim.OutPick`, simulator `7544249E-D0EE-4B88-A48F-E384DF84E6A4`.
- Phase 5 수동 QA 후 비디오 전송 UX 보정 완료.
  - 기존에는 비디오 업로드 시 화면 중앙 `CircularProgressHUD`가 뜨고 성공 후 사라지지 않는 문제가 있었다.
  - 비디오 변환 완료 후 `PreparedVideo` 썸네일을 사용해 pending video message를 먼저 timeline에 추가하도록 변경했다.
  - 비디오 업로드 progress는 이미지 pending upload와 같은 attachment overlay ring을 사용한다.
  - 성공 시 같은 `messageID`로 `VideoMetaPayload`를 보내 서버 메시지가 pending video message를 대체하도록 했다.
  - 업로드 실패 시 중복 failed video message를 만들지 않고 pending video message 자체를 failed 상태로 표시한다.
  - `ChatMediaUploadUseCaseTests`에 pending video preview attachment 생성 테스트를 추가했다.
  - `ChatPendingMediaUploadStoreTests`에 video upload state/task 중복 방지 테스트를 추가했다.
- 비디오 전송 UX 보정 검증 통과.
  - `xcodebuildmcp.test_sim` with `-only-testing:OutPickTests/ChatMediaUploadUseCaseTests`, `-only-testing:OutPickTests/ChatPendingMediaUploadStoreTests`
  - 10개 통과.
  - `xcodebuildmcp.build_run_sim` 통과.
- Phase 5 검증에서도 기존 warning이 남아 있다.
  - `LoadChatRoomParticipantsUseCase` main actor isolation warning.
  - functions node_modules linker search path warning.
- Phase 6 진입 전 `xcodebuildmcp.session_show_defaults` 확인 결과 `OutPick.xcodeproj` / `OutPick` / `iPhone 17 Pro Max` 기본값이 설정되어 있었다.
- Phase 6 Store 관련 targeted unit test 실행 통과.
  - `xcodebuildmcp.test_sim` with `-only-testing:OutPickTests/ChatReadStateStoreTests`, `-only-testing:OutPickTests/ChatMessageWindowStoreTests`, `-only-testing:OutPickTests/ChatPendingMediaUploadStoreTests`
  - 14개 통과.
- Phase 6 앱 빌드/실행 검증 통과.
  - `xcodebuildmcp.build_run_sim`
  - bundle id `GayoonKim.OutPick`, simulator `7544249E-D0EE-4B88-A48F-E384DF84E6A4`.
- Phase 6 검증에서도 기존 warning이 남아 있다.
  - `ChatViewController.swift` 등 기존 `contentEdgeInsets` deprecation warning.
  - `LoadChatRoomParticipantsUseCase` main actor isolation warning.
  - functions node_modules linker search path warning.
- Phase 6 보강 첫 targeted unit test는 `ChatContainer` init 기본 인자에서 `@MainActor` `ChatRoomReadStateStore()`를 생성해 실패했다.
- `ChatContainer` init 내부에서 optional store를 resolve하도록 수정했다.
- Phase 6 보강 두 번째 targeted unit test는 `JoinedRoomsUseCase`가 `@MainActor` shared Store를 직접 조회해 실패했다.
- Store 조회/seed 책임을 `JoinedRoomsViewModel`로 이동하고, `JoinedRoomsUseCase`는 서버 snapshot fetch만 제공하도록 수정했다.
- Phase 6 보강 targeted unit test 실행 통과.
  - `xcodebuildmcp.test_sim` with `-only-testing:OutPickTests/ChatRoomReadStateStoreTests`, `-only-testing:OutPickTests/ChatReadStateStoreTests`, `-only-testing:OutPickTests/ChatRoomViewModelMessageActionTests`
  - 12개 통과.
- Phase 6 보강 관련 확장 targeted unit test 실행 통과.
  - `xcodebuildmcp.test_sim` with `-only-testing:OutPickTests/ChatRoomReadStateStoreTests`, `-only-testing:OutPickTests/ChatReadStateStoreTests`, `-only-testing:OutPickTests/ChatRoomViewModelMessageActionTests`, `-only-testing:OutPickTests/LookbookChatShareUseCaseTests`
  - 23개 통과.
- Phase 6 보강 앱 빌드/실행 검증 통과.
  - `xcodebuildmcp.build_run_sim`
  - bundle id `GayoonKim.OutPick`, simulator `7544249E-D0EE-4B88-A48F-E384DF84E6A4`.
- Phase 6 보강 사용자 수동 QA 완료.
  - read-state Store 기반 참여중인 목록 unread 갱신 정상 동작 확인.
  - 현재 채팅방 읽음 상태 공유 정상 동작 확인.
