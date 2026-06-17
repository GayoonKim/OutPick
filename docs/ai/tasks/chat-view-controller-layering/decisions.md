# ChatViewController Layering Decisions

## 결정 인덱스

- 공식 아키텍처 기준:
  - `docs/ai/CODE_ARCHITECTURE.md`
  - `docs/ai/SCREEN_SPEC.md`
  - `docs/ai/FLOW.md`
- 이전 task 근거:
  - `docs/ai/tasks/lookbook-chat-share/progress.md`
  - `docs/ai/tasks/lookbook-chat-share/plan.md`

## 결정: 독립 task로 승격

결정:

- `ChatViewController.swift` 레이어 분리는 `lookbook-chat-share`의 후속 작업 후보에서 독립 task로 승격한다.

이유:

- 공유 MVP는 완료 상태로 기록되어 있다.
- `ChatViewController` 분리는 채팅 전체 안정성과 직접 연결되는 큰 리팩토링이다.
- 공유 기능과 같은 task에 계속 붙이면 phase 범위와 검증 기준이 흐려진다.

영향:

- `docs/ai/tasks/active.md`는 새 task를 가리킨다.
- 이전 공유 기능 문서는 배경과 근거로만 참조한다.

## 결정: 파일 분할보다 책임 이동 우선

결정:

- `ChatViewController+Send.swift` 같은 단순 extension 파일 분리만으로 phase를 완료하지 않는다.
- 각 phase는 책임의 소유권을 ViewModel, UseCase, Repository, Service, Coordinator 중 하나로 이동해야 완료로 본다.

이유:

- 단순 파일 분할은 탐색성은 조금 좋아지지만 구조적 결합은 그대로 남긴다.
- 현재 문제는 줄 수보다 Socket/Firebase/Storage/GRDB와 UI state가 한 객체 안에 섞인 점이다.

영향:

- phase별 변경은 작게 유지하되, 새 경계와 테스트 가능성을 남긴다.

## 결정: 첫 코드 phase는 텍스트 메시지 전송

결정:

- Phase 1은 텍스트 메시지 전송 경계 분리로 시작한다.

이유:

- `handleSendButtonTap`은 범위가 작고 성공/실패 동작이 비교적 명확하다.
- 문서상 후속 후보인 "메시지 전송을 UseCase/Repository 경계로 이동"과 정확히 맞는다.
- 미디어 업로드보다 회귀 반경이 작다.

영향:

- Phase 1에서 `SocketIOManager.shared.sendMessage` 직접 호출을 ViewController 밖으로 이동한다.
- optimistic render와 failed message 표시를 보존해야 한다.

## 결정: 미디어 업로드는 후반 phase로 둔다

결정:

- 이미지/비디오 업로드 분리는 Phase 5로 미룬다.

이유:

- pending image message, local preview, upload progress, retry, Firebase Storage, socket broadcast, media cache가 서로 얽혀 있다.
- 초반에 건드리면 채팅 기본 흐름 회귀 위험이 크다.

영향:

- Phase 1~4에서 미디어 업로드 동작은 가능한 건드리지 않는다.
- `ChatMediaManaging.uploadCompressedVideoAndBroadcast`의 fatalError 제거는 Phase 5에서 다룬다.

## 결정: snapshot-only 룩북 공유 원칙 유지

결정:

- `lookbookShare` 메시지 렌더링은 계속 `sharedContent` snapshot만 사용한다.
- Chat이 룩북 Repository를 직접 조회하지 않는다.

이유:

- 기존 ADR와 공유 MVP 원칙을 유지한다.
- 채팅방 진입/스크롤 성능과 실패 독립성을 지키기 위해서다.

영향:

- Phase 4/5에서 cell/data source를 분리하더라도 룩북 원본 조회를 추가하지 않는다.

## 완료한 추가 결정

### iOS 검증 도구 우선순위

결정:

- Phase 4 이후 iOS 앱 빌드, 테스트, 실행, 시뮬레이터 확인은 가능한 경우 Build iOS Apps 플러그인의 `xcodebuildmcp` 도구를 우선 사용한다.
- 첫 build/run/test 호출 전에는 `session_show_defaults`로 active project/workspace, scheme, simulator를 확인한다.
- 기본값이 맞으면 `build_run_sim`, `test_sim`, `launch_app_sim`, `screenshot` 같은 목적별 도구를 사용한다.
- 플러그인이 지원하지 않는 특수 검증이나 비교를 위해 필요한 경우에만 shell `xcodebuild`를 사용한다.

이유:

- 현재 task는 Swift 코드 수정 후 빌드, targeted test, 수동 QA가 반복된다.
- `xcodebuildmcp`는 project/scheme/simulator 기본값과 simulator 실행 흐름을 유지하므로 반복 검증 비용을 줄일 수 있다.
- 앱 실행, 로그, 스크린샷 확인까지 같은 도구 경계에서 이어갈 수 있어 UI 회귀 확인이 쉬워진다.

영향:

- 다음 phase 검증 계획에는 `xcodebuildmcp` 사용 여부와 fallback으로 shell `xcodebuild`를 썼는지 기록한다.
- 검증 결과는 기존처럼 `progress.md`에 남긴다.

### optimistic message 생성 위치

결정:

- UseCase가 생성한다.

이유:

- sender snapshot, message ID, sentAt, reply preview를 포함한 전송용 도메인 결과를 UI 밖에서 만들 수 있다.
- Repository는 socket adapter에 집중한다.
- 테스트에서 optimistic payload를 검증하기 쉽다.

영향:

- ViewController는 입력만 전달한다.
- ViewController는 UseCase가 만든 message를 먼저 optimistic render하고, 그 뒤 prepared message 전송만 ViewModel에 요청한다.

### 실시간 stream 소유권

결정:

- B안을 채택한다.
- Repository/UseCase는 `AsyncStream<ChatMessage>`를 제공한다.
- `ChatRoomRealtimeSubscription`이 runtime task, session close/cancel, stale subscription finish 방지를 소유한다.
- ViewModel은 stream open API와 live/catching-up 상태 판단만 맡는다.
- ViewController는 subscription 시작/중지만 수행한다.

이유:

- `SocketIOManager.openRoomSession` 의존을 ViewController 밖으로 이동할 수 있다.
- ViewController가 `ChatRoomSocketSession`, stream token, socket task를 직접 들지 않는다.
- 기존 live/catching-up buffering 로직은 ViewModel에 그대로 남겨 회귀 반경을 줄인다.
- subscription identity로 기존 token의 stale stream cleanup 보호를 유지한다.

영향:

- Phase 2에서 `ChatRoomRealtimeRepositoryProtocol`, `ChatRoomRealtimeUseCase`, `ChatRoomRealtimeSubscription`이 추가됐다.
- fake repository 기반 stream 계약 테스트가 가능해졌다.

### 메시지 액션 실행 경계

결정:

- B안을 채택한다.
- 권한 계산은 `ChatMessageActionPolicy` 순수 객체에 유지한다.
- 메뉴 선택 이벤트는 `ChatMessageAction` 값으로 전달한다.
- delete/announce처럼 서버 상태를 바꾸는 액션은 `ChatRoomViewModel.performMessageServerAction`을 통해 UseCase 경계로 이동한다.
- reply/copy/report toast처럼 UIKit 로컬 UI feedback 성격의 액션은 Phase 3에서 ViewController에 남긴다.
- report는 기존처럼 "메시지가 신고되었습니다." toast만 유지하고, 실제 신고 저장/서버 처리는 후속 기능 phase에서 별도 설계한다.

이유:

- Phase 3 목표는 기능 추가가 아니라 책임 분리다.
- 실제 신고 기능은 UGC/신고 데이터/정책/운영 처리/API 설계가 섞이므로 별도 phase로 분리하는 편이 안전하다.
- `ChatViewController`에서 `messageManager.deleteMessage` 직접 호출 우회로를 제거하면서도 UI 회귀 범위를 작게 유지할 수 있다.

장점:

- 회귀 범위가 작다.
- action policy 테스트를 유지할 수 있다.
- UI feedback과 서버 상태 변경의 경계가 명확하다.

단점:

- ViewController에 일부 UI action 처리 코드가 남는다.

### 삭제 메시지 목록 요약 갱신

결정:

- 삭제 대상 메시지가 방의 현재 마지막 메시지일 때만 `Rooms/{roomID}.lastMessage`를 "삭제된 메시지입니다."로 갱신한다.
- 갱신 여부는 Firestore transaction 안에서 room의 `seq` 또는 `lastMessageSeq`와 삭제 대상 메시지 `seq`를 비교해 판단한다.
- 삭제 요약 갱신 시 `lastMessageAt`은 변경하지 않는다.
- 오픈채팅 목록의 메시지 preview 배열 렌더링은 `isDeleted`를 본문/첨부보다 먼저 판단한다.

이유:

- 참여중인 목록은 room aggregate의 `lastMessage`를 사용하므로 메시지 문서만 삭제 상태로 바꾸면 pull-to-refresh 후에도 원문이 남을 수 있다.
- 삭제 직후 새 메시지가 들어온 경우 단순 update는 최신 메시지 요약을 덮어쓸 수 있다.
- 삭제 액션만으로 방 정렬을 최신순 상단으로 올리는 것은 기존 채팅 목록 정렬 기대와 다를 수 있다.
- 오픈채팅 목록은 room aggregate와 별도로 message preview 배열을 그리는 경로가 있어 렌더링 방어선도 필요하다.

영향:

- `ChatRoomMessageUseCase.deleteMessage`가 삭제 처리 뒤 optional summary updater를 호출한다.
- `FirebaseChatRoomRepository`가 `ChatDeletedLastMessageSummaryUpdating` 경계를 구현한다.
- `RoomListCollectionViewCell.MessagePreviewView`는 삭제 메시지를 항상 "삭제된 메시지입니다."로 표시한다.

### 메시지 list item 타입 위치

결정:

- B안을 채택했다.
- `ChatViewController.Item` 내부 enum을 유지하지 않고 `ChatMessageListItem`으로 승격한다.
- 메시지 window/list item/reconfigure 계산은 `ChatMessageWindowStore`가 소유한다.
- Phase 4에서는 pending image upload 상태를 store의 메시지 상태 갱신에만 연결하고, 업로드 task/pair/processing 분리는 Phase 5로 유지한다.

이유:

- Phase 4의 목표는 목록 구성 로직을 ViewController 밖에서 검증 가능하게 만드는 것이다.
- `ChatViewController.Item`을 유지하면 store가 ViewController 내부 타입에 묶여 테스트성과 책임 분리 효과가 약해진다.
- pending upload까지 함께 분리하면 Phase 5 범위와 섞여 회귀 반경이 커진다.

장점:

- 날짜 구분선/read marker/메시지 item 생성을 UI 밖에서 검증할 수 있다.
- 중복 제거, virtualization, reconfigure 대상 산출을 unit test로 고정할 수 있다.
- `ChatViewController.addMessages`가 store mutation 결과를 snapshot에 적용하는 역할로 줄어든다.

단점:

- 기존 data source generic 타입 변경이 필요하다.

영향:

- `OutPick/Features/Chat/Stores/ChatMessageWindowStore.swift`가 추가됐다.
- `OutPickTests/ChatMessageWindowStoreTests.swift`가 추가됐다.
- Phase 5에서는 남아 있는 pending image upload state/task/pair와 미디어 처리 책임을 이어서 분리한다.

### 이미지/비디오 pending upload 분리 경계

결정:

- 이미지와 비디오 업로드 경계는 `ChatMediaUploadUseCase`로 묶는다.
- pending image/video의 상태, 원본 pair, retry payload, upload task 중복 방지는 `ChatPendingMediaUploadStore`가 소유한다.
- socket media broadcast는 `ChatMediaMessageSendingRepositoryProtocol` 뒤로 숨긴다.
- pending preview attachment 파일 생성과 local preview cleanup은 `ChatMediaUploadUseCase`가 담당한다.
- 비디오 업로드는 pending video message와 attachment overlay progress를 사용하되, retry payload는 pending image와 완전히 통합하지 않는다.
- `ChatMediaManaging.uploadCompressedVideoAndBroadcast`의 fatalError 계약은 제거한다.

이유:

- 이미지 pending upload는 progress overlay, retry, local preview 파일이 있어 상태 소유권이 필요하다.
- 비디오 업로드는 사용자 QA 후 화면 중앙 HUD 대신 pending thumbnail과 attachment overlay progress로 맞췄다.
- Storage와 Socket 직접 호출을 ViewController 밖으로 이동하면 fake repository 기반 테스트가 가능해진다.
- `ChatMediaManaging`은 캐시/프리페치/재생/저장 보조 책임에 집중하고, 업로드 orchestration은 UseCase가 맡는 편이 책임 경계가 명확하다.

영향:

- `OutPick/Features/Chat/Domain/UseCases/ChatMediaUploadUseCase.swift`가 추가됐다.
- `OutPick/Features/Chat/Stores/ChatPendingMediaUploadStore.swift`가 추가됐다.
- `OutPick/Features/Chat/Repositories/ChatMediaMessageSendingRepository.swift`가 추가됐다.
- `OutPickTests/ChatMediaUploadUseCaseTests.swift`와 `OutPickTests/ChatPendingMediaUploadStoreTests.swift`가 추가됐다.
- Phase 6 이후에도 비디오 retry UX 통합은 별도 제품/UX 결정이 필요할 때 후속 phase로 다룬다.

### Chat Store 파일 위치

결정:

- Store 파일이 2개 이상 생긴 시점부터 `OutPick/Features/Chat/Stores/` 폴더를 사용한다.
- 기존 `ChatMessageWindowStore`와 `ChatPendingMediaUploadStore`도 `ViewModels` 폴더에서 `Stores` 폴더로 이동한다.

이유:

- Store는 ViewModel 내부 구현 보조 객체지만, 여러 파일이 생기면 ViewModel 파일과 같은 폴더에 계속 두는 것보다 책임군 기준 탐색성이 좋다.
- `Stores` 폴더를 두면 Phase 6 이후에도 상태 계산 객체를 ViewModel과 분리해 찾기 쉽다.

영향:

- `OutPick/Features/Chat/Stores/ChatMessageWindowStore.swift`
- `OutPick/Features/Chat/Stores/ChatPendingMediaUploadStore.swift`
- `OutPick/Features/Chat/Stores/ChatReadStateStore.swift`
- `OutPick/Features/Chat/Stores/ChatRoomReadStateStore.swift`

### 읽음 seq 상태 분리

결정:

- Phase 6에서는 읽음 seq 후보 계산, final seq 계산, pending/queued/persisted 상태 전이를 `ChatReadStateStore`로 분리한다.
- debounce task와 `ChatRoomLifecycleUseCase.updateLastReadSeq` 호출 orchestration은 `ChatRoomViewModel`에 유지한다.
- app lifecycle observer와 near-bottom 판정은 `ChatViewController`에 유지한다.

이유:

- 읽음 seq의 숫자 상태 전이는 순수 로직으로 분리하면 unit test로 고정하기 쉽다.
- lifecycle observer까지 한 번에 runtime object로 옮기면 앱 background/terminate 타이밍 회귀 반경이 커진다.
- `ChatViewController`는 아직 collection view scroll 위치를 가장 정확히 알고 있으므로 near-bottom 판정은 UI 계층에 남기는 편이 안전하다.

영향:

- `ChatRoomViewModel`은 read seq 숫자 필드 세 개를 직접 소유하지 않는다.
- `OutPickTests/ChatReadStateStoreTests.swift`가 추가됐다.
- 후속 phase에서 lifecycle observer까지 이동하려면 별도 runtime/controller 설계가 필요하다.

### 읽음 상태 공유 Store와 Notification 제거

결정:

- Phase 6 보강으로 `NotificationCenter.chatRoomLastReadSeqDidFlush` 경로를 제거한다.
- 단일 방 flush 상태 머신 `ChatReadStateStore`는 유지한다.
- 여러 화면이 공유해야 하는 roomID별 read/latest snapshot은 `ChatRoomReadStateStore`가 소유한다.
- `ChatRoomReadStateStore`는 `AsyncStream<ChatRoomReadStateChange>`로 변경 이벤트를 발행한다.
- `JoinedRoomsViewModel`은 shared Store stream을 구독해 unread count를 즉시 갱신한다.
- 서버 조회는 초기 bootstrap, tail load, pull-to-refresh/복구 성격의 seed에 남긴다.

이유:

- 참여중인 목록과 현재 채팅방은 같은 읽음 상태를 공유해야 한다.
- 기존 `NotificationCenter` 방식은 flush 이벤트를 화면 간에 전달할 뿐, read/latest snapshot의 local source of truth를 제공하지 못한다.
- shared Store를 두면 메시지 수신, room summary 갱신, flush 성공 시 서버 재조회를 강제하지 않고 unread UI를 갱신할 수 있다.
- 서버 seed를 유지하면 앱 재시작, 다른 기기 읽음 처리, local snapshot 누락 상황에서도 복구 가능하다.

영향:

- `ChatContainer`가 `ChatRoomReadStateStore`를 생성하고 `JoinedRoomsViewModel`, `ChatRoomViewModel`에 주입한다.
- storyboard fallback을 위해 `ChatDependencyContainer.requireRoomReadStateStore()`를 추가했다.
- `JoinedRoomsUseCase`는 unread count 숫자뿐 아니라 서버 기준 `ChatRoomReadSnapshot`을 가져오는 경계를 제공한다.
- `ChatViewController`는 더 이상 `.chatRoomLastReadSeqDidFlush` notification을 발행하지 않는다.
- `JoinedRoomsViewController`는 더 이상 `.chatRoomLastReadSeqDidFlush` notification을 구독하지 않는다.
- `ChatNotifications.swift`는 삭제됐다.

## 미결정 사항

- 없음. Phase 6은 추천안대로 진행했다.
