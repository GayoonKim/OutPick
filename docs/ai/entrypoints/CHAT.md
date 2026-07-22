# Chat Entrypoints

## 목적

Chat 기능 수정 시 관련 화면, ViewModel, UseCase, Repository, 검색 인덱스 진입점을 빠르게 찾기 위한 문서다.

## 방 목록 검색

- 화면: `OutPick/Features/Chat/Controllers/RoomSearchViewController.swift`
- ViewModel: `OutPick/Features/Chat/ViewModels/RoomSearchViewModel.swift`
- UseCase: `OutPick/Features/Chat/Domain/UseCases/RoomSearchUseCase.swift`
- Repository protocol: `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`
- Repository implementation: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
- 검색 인덱스 모델: `OutPick/Features/Chat/Domain/Models/ChatRoomSearchIndex.swift`
- Room 저장 인덱스 반영: `OutPick/DB/Firebase/DatabaseManager/Mappers/ChatRoomFirestoreMapper.swift`
- Firestore indexes: `firestore.indexes.json`
- Firestore room/message/media preview read rules: `firestore.rules`

방 목록 검색은 방 이름과 방 설명에서 자동 생성한 검색 token을 기준으로 동작한다. 입력과 상태 흐름은 `RoomSearchViewModel`의 Combine state publisher가 소유하고, 방 선택 같은 단발 라우팅 이벤트는 `RoomSearchViewController`의 클로저를 유지한다.

검색창 외 영역 탭 시 키보드 dismiss는 `KeyboardDismissSupport.installKeyboardDismissTapGesture()`로 처리한다.

## 전체 채팅방 목록 미리보기

- 화면: `OutPick/Features/Chat/Controllers/RoomListsCollectionViewController.swift`
- 셀: `OutPick/Features/Chat/Views/Cell/RoomListCollectionViewCell.swift`
- 화면 조립/DI: `OutPick/Features/Chat/ChatCoordinator.swift`
- ViewModel: `OutPick/Features/Chat/ViewModels/RoomListsViewModel.swift`
- UseCase: `OutPick/Features/Chat/Domain/UseCases/RoomListUseCase.swift`
- Repository protocol: `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`
- Repository implementation: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
- 방 커버 이미지: `OutPick/Features/Chat/Services/ImageLoading/RoomImageService.swift`
- 메시지 발신자 avatar: `OutPick/Features/Chat/Services/ImageLoading/AvatarImageService.swift`
- 이미지 메모리/디스크 캐시: `OutPick/Infra/Cache/ImageCache/ImageCachePipeline.swift`

전체 채팅방 목록은 `Rooms.lastMessageAt DESC` 기준으로 방을 가져오고, 각 방의 최근 메시지 3개를 함께 불러와 미리보기로 표시한다. `ChatCoordinator`는 room/avatar image manager를 목록 화면에 주입한다. `RoomListsCollectionViewController`는 `UICollectionViewDataSourcePrefetching`으로 곧 보일 방의 커버 이미지와 상대방 메시지 `senderAvatarPath`를 미리 캐시에 적재한다. 셀 구성 시 `RoomListCollectionViewCell`은 주입받은 room/avatar image manager를 사용해 캐시를 먼저 확인하고, 없으면 Storage에서 로드한다. 내 메시지 미리보기는 avatar를 숨기고, 상대방 메시지 미리보기만 avatar를 표시한다. 이미지 캐시 정책은 `RoomImageService`/`AvatarImageService`가 `ImageCachePipeline`을 통해 메모리와 전용 디스크 캐시에 저장하는 흐름을 따른다. 컬렉션 뷰 하단은 메인 탭 바와 겹치지 않도록 `view.safeAreaLayoutGuide.bottomAnchor`에 맞춘다.

## 비참여 채팅방 Preview

- 화면: `OutPick/Features/Chat/Controllers/ChatViewController.swift`
- 초기 로드: `OutPick/Features/Chat/Domain/UseCases/ChatInitialLoadUseCase.swift`
- 조립: `OutPick/Features/Chat/ChatContainer.swift`
- Firestore rules: `firestore.rules`

비참여 사용자는 전체 채팅방 목록/검색에서 방을 열어 메시지, 이미지 버블, 비디오 썸네일/메타를 미리 볼 수 있다. 단, 참여 전에는 뒤로가기와 하단 input bar 위치의 참여하기 버튼 외 상호작용을 막는다. 이미지 확대, 동영상 재생, 설정/검색, 메시지 전송/첨부, retry, 메시지 메뉴, 발신자 프로필/룩북 공유 이동 같은 참여자 전용 동작은 `ChatViewController`의 preview guard에서 차단한다.

채팅방은 `ChatViewController.backgroundTapGesture`가 키보드, attachment, message menu 닫기를 한 곳에서 담당한다. text input과 일반 `UIControl` superview chain touch는 제외하고, message/media/profile/retry/Lookbook cell tap은 `cancelsTouchesInView = false`와 동시 인식으로 원래 action과 background dismiss를 함께 실행한다. `ChatMessageCell` 내부 retry control도 cell action 우선순위로 허용한다. message long press는 `chatMessageCollectionView`, announcement long press와 settings dim tap은 각 leaf view가 소유한다. 공통 `KeyboardDismissSupport` 중복 설치는 Chat에서 사용하지 않는다.

## 참여중 채팅방 목록

- 화면: `OutPick/Features/Chat/Controllers/JoinedRoomsViewController.swift`
- ViewModel: `OutPick/Features/Chat/ViewModels/JoinedRoomsViewModel.swift`
- UseCase: `OutPick/Features/Chat/Domain/UseCases/JoinedRoomsUseCase.swift`
- Repository protocol: `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`
- Repository implementation: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
- Firestore indexes: `firestore.indexes.json`
- Shared read state: `OutPick/Features/Chat/Stores/ChatRoomReadStateStore.swift`
- App-running banner stream: `OutPick/Infra/Banner/BannerManager.swift`
- 하단 레이아웃: `OutPick/Features/Chat/Controllers/JoinedRoomsViewController.swift`

참여중 채팅방 목록은 Firestore realtime listener를 사용하지 않는다. 화면 진입/앱 재실행 시 단발 fetch로 authoritative snapshot을 만들고, 사용자가 pull-to-refresh로 재동기화한다. 앱 실행 중 참여중 방에 새 메시지가 도착하는 경우에는 `BannerManager`의 socket stream이 `ChatRoomReadStateStore`와 `FirebaseChatRoomRepository`의 local preview cache를 갱신해 목록 화면에 unread/마지막 메시지를 즉시 반영한다. 현재 목록 source는 `users/{uid}/joinedRooms/{roomID}` projection이며, 해당 roomID로 `Rooms` 문서를 batch fetch한 뒤 클라이언트에서 `Rooms.lastMessageAt DESC`로 정렬한다.

대형 membership 전환 후 현재 계약:

- 참여중 목록은 `users/{uid}/joinedRooms/{roomID}` projection을 단발 fetch/pull-to-refresh로 읽는다.
- projection에는 `roomID`, `role`, `joinedAt`, `lastReadSeq`, `isClosed`, `updatedAt`만 둔다.
- 전체 참여자 배열과 `unreadCount`는 projection에 넣지 않는다.
- `lastMessage`, `lastMessageAt`, `lastMessageSeq`는 `Rooms/{roomID}` 문서만 source로 사용한다.
- 참여중 목록은 joinedRooms 전체 또는 충분한 범위 fetch 후 `Rooms` batch fetch, `Rooms.lastMessageAt DESC` 클라이언트 정렬로 구성한다.
- 메시지 전송 시 Socket 서버의 seq transaction이 room metadata의 `lastMessage*`를 즉시 갱신하며, 사용자별 projection의 `lastMessage*` fan-out은 하지 않는다.
- cutover 후 사용자 프로필 문서의 `joinedRooms` 배열은 bootstrap/runtime source로 사용하지 않는다.
- 관련 task: `docs/ai/tasks/chat-membership-model-transition/*`
- 참여중 목록 컬렉션 뷰 하단은 메인 탭 바와 겹치지 않도록 `view.safeAreaLayoutGuide.bottomAnchor`에 맞춘다.

## Realtime, Banner, Read State

- Socket transport: `OutPick/Infra/Realtime/RealtimeSocketService.swift`
- Socket listener one-time binding: `OutPick/Infra/Realtime/RealtimeSocketListenerBinder.swift`
- Socket server bootstrap: `Socket/index.js`
- Socket application/production DI: `Socket/src/app/createSocketApplication.js`, `Socket/src/app/createProductionDependencies.js`
- Socket 인증/event 등록: `Socket/src/auth/`, `Socket/src/handlers/`
- Socket room/message/media 작업 단위: `Socket/src/rooms/`, `Socket/src/messages/`, `Socket/src/media/`
- Socket message single-flight/outcome: `Socket/src/messages/messageDeliverySingleFlight.js`, `Socket/src/messages/sequenceStore.js`
- Socket lifecycle/runtime: `Socket/src/lifecycle/`, `Socket/src/runtime/`
- Socket 검증: `Socket/test/`, `Socket/scripts/run-tests.mjs`
- 현재 채팅방 stream 연결: `OutPick/Features/Chat/Controllers/ChatViewController.swift`
- 읽음/안 읽음 shared store: `OutPick/Features/Chat/Stores/ChatRoomReadStateStore.swift`
- 화면 read frontier 순수 상태: `OutPick/Features/Chat/Stores/ChatReadStateStore.swift`
- 대규모 unread/latest jump 순수 상태: `OutPick/Features/Chat/Domain/Models/ChatUnreadCatchUpState.swift`
- 앱 실행 중 방 밖 메시지 banner: `OutPick/Infra/Banner/BannerManager.swift`
- 전체 방 목록 preview cache: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
- 참여중 목록 즉시 반영: `OutPick/Features/Chat/ViewModels/JoinedRoomsViewModel.swift`
- 전체 방 목록 즉시 반영: `OutPick/Features/Chat/ViewModels/RoomListsViewModel.swift`

채팅방 화면을 보고 있을 때는 initial load의 `entryTailSeq`가 Controller→ViewModel→UseCase→Repository를 지나 `RealtimeSocketService.openVisibleRoomSession(for:baselineSeq:)`에 전달된다. room join ACK 뒤 `ChatRoomStrictSessionActor`가 `entryTailSeq + 1`부터 연속 seq만 stream으로 release하고 수신 메시지는 ViewModel/GRDB 저장 경로를 거쳐 현재 화면에 반영된다.

Socket의 text/Lookbook/images/video message callback은 `RealtimeSocketMessageIngressQueue`에 동기 enqueue되고 단일 consumer가 순서대로 decode한다. `RealtimeSocketService`의 공통 admission은 joined room별 최근 message ID 300개를 first-wins로 제거한 뒤 routing한다. 방 탈퇴·로그아웃/UID 변경에서는 해당 상태를 제거하고, local `seq == 0` 메시지는 admission을 우회해 같은 ID의 후속 서버 확정 event를 차단하지 않는다.

`RealtimeRoomRoutingState`는 `roomID + generation` visible lease, initial `entryTailSeq` baseline과 background high watermark를 보관한다. promotion은 현재 background watermark를 recovery 상한으로 캡처하고 stale lease 종료는 새 visible route를 해제하지 못한다. Chat strict stream과 Banner background stream은 분리됐지만 visible event도 read-state/room preview 갱신을 위해 background actor에 전달되며 `BannerManager`가 visible room UI만 억제한다.

`ChatRoomStrictSessionActor`는 pending 100개에서 즉시 recovery, 300개 payload hard cap, 0.5초 grace, 100개 ASC page와 최대 3회 retry를 사용한다. `ChatRealtimeGapRecoveryLoading`은 roomID/afterSeq/limit만 노출하고 production 구현은 `FirebaseChatRealtimeGapRecoveryLoader`이며 `AppCompositionRoot`가 단일 service에 주입한다. 기존 `ChatRoomSessionActor`의 최근 ID 300개 first-wins 검사는 background fan-out 최종 방어선으로 남는다. background/네트워크 disconnect에서는 checkpoint·pending·recent ID를 보존하고 timer/recovery만 중지하며, 성공한 같은 방 rejoin ACK 뒤 `lastReleasedSeq` 다음부터 즉시 감사한다. permission-denied/not-found는 terminal로 변환해 strict stream을 종료한다.

`ChatRoomRouteLifecycleState`는 UIKit appearance와 실제 route 소유권을 분리하며 terminal finish는 비가역이다. `ChatViewController.viewWillDisappear`는 strict stream을 닫지 않으며, `viewDidDisappear`에서 navigation stack 제거 또는 modal dismiss가 확정됐을 때 `ChatCoordinator`의 `onRouteRemoved` callback이 stream과 room-close observation을 종료한다. 취소된 interactive pop과 자식 화면 복귀에서는 realtime/search binding과 사용자 활성 상태를 복원하되, terminal route는 어떤 appearance에서도 다시 활성화하지 않는다.

두 Chat root는 `ChatNavigationController`를 사용한다. stack과 push/pop animation은 UIKit 기본 구현을 유지하고, system `interactivePopGestureRecognizer`의 delegate만 Chat 전용 안전 delegate로 교체한다. root stack 또는 active transition에서는 시작을 거부하고 일반 push 화면에서는 leading-edge pop을 허용한다. 화면이 `ChatInteractivePopControlling`으로 거부하면 pop을 시작하지 않으며, `RoomCreateViewController`는 작성 내용의 무확인 유실을 막기 위해 항상 거부한다. 방 생성 이탈은 커스텀 navigation bar의 Back 버튼과 기존 취소 확인창만 사용한다. iOS 26 `interactiveContentPopGestureRecognizer`는 비활성화하지 않는다. 2026-07-22 A/B에서 content-pop만 끈 설정은 실패했고 edge delegate만 교체한 설정은 수동 swipe가 통과했다.

Phase 7에서 호출자가 없던 navigation/modal interactive transition extension과 `PushAnimator`/`PopAnimator`를 제거했다. UIKit 전역 타입의 retroactive navigation/transition delegate conformance는 더 이상 없으며, 실제 Profile modal 경로가 사용하는 `ChatModalTransitionManager`는 유지한다.

같은 navigation stack에서 다른 Chat을 열 때는 `ChatNavigationStackPolicy`가 기존 Chat route를 stack에서 제거하고 non-Chat prefix를 보존한 뒤 새 Chat을 배치한다. 따라서 `목록 → A → B → Back → A` 형태의 종료 route 부활을 허용하지 않는다. 오픈채팅과 참여중 목록은 서로 다른 navigation stack을 계속 소유하므로 탭별 방문 기록은 독립적으로 유지된다.

room ID만 가진 외부 진입은 `ChatCoordinator.openRoom`이 stack별 request gate를 소유한다. `ChatOpenRoomRequestState`가 current token을, `ChatOpenRoomRequestRegistry`가 실제 공유 Task와 정리를 소유한다. 같은 stack·room·snapshot 요청은 동일 Task에 합류하고, 같은 stack의 다른 room은 latest-wins, 다른 stack 요청은 독립 실행한다. 완료 시 token과 navigation snapshot을 다시 검사하므로 같은 target stack에서 직접 방을 열거나 Back/검색/방 생성으로 stack이 변한 이전 결과는 stale drop된다. 단순 탭 전환은 target stack snapshot을 바꾸지 않으며 현재 탭을 강제로 전환하지 않는다. 실제 최신 요청 오류만 호출자에게 전달하고 superseded/stale 완료는 사용자 오류 없이 종료한다.

### Route/lifecycle/gesture 변경 파일 빠른 지도

| 알고 싶은 내용 | 먼저 볼 파일 | 확인할 코드 책임 |
| --- | --- | --- |
| 오픈채팅·참여중 root navigation 조립, 외부 room 진입과 같은 stack 교체 | `OutPick/Features/Chat/ChatCoordinator.swift` | 두 root를 `ChatNavigationController`로 만들고, `openRoom` request gate와 `presentChatRoom` stack mutation을 연결한다. |
| UIKit leading-edge pop 허용/차단 | `OutPick/Features/Chat/ChatNavigationController.swift` | system edge recognizer delegate, root/active transition 차단, `ChatInteractivePopControlling` 화면별 opt-out을 소유한다. iOS 26 content-pop은 유지한다. |
| 방 생성 화면의 edge-pop 차단과 기존 취소 흐름 | `OutPick/Features/Chat/Controllers/RoomCreateViewController.swift` | `allowsChatInteractivePop == false`로 swipe를 차단하고 기존 custom Back/취소 확인창을 유지한다. |
| 같은 stack의 Chat 배치 결과 | `OutPick/Features/Chat/ChatNavigationStackPolicy.swift` | non-Chat prefix 보존, 기존 Chat 제거, top same-room no-op를 순수 정책으로 계산한다. |
| 같은 stack·같은 room 합류와 stale token 판정 | `OutPick/Features/Chat/ChatOpenRoomRequestState.swift` | stack별 current token, room, navigation snapshot과 stale completion 판정을 소유한다. |
| 실제 fetch Task 공유·취소·정리 | `OutPick/Features/Chat/ChatOpenRoomRequestRegistry.swift` | same-room Task coalesce, same-stack latest-wins, 다른 stack 독립과 실패 후 retry entry 정리를 소유한다. |
| terminal finish와 transient 복귀 가능 여부 | `OutPick/Features/Chat/ChatRoomRouteLifecycleState.swift` | pop/dismiss/replacement의 비가역 finish와 취소 pop/자식 화면 복귀 상태를 순수하게 판정한다. |
| Chat route appearance, background dismiss, message long press 설치 위치 | `OutPick/Features/Chat/Controllers/ChatViewController.swift` | route 종료/복귀 wiring, root `backgroundTapGesture`, collection view `messageLongPressGesture`, settings dim과 announcement gesture owner를 확인한다. |
| background tap이 받을 touch와 cell action 동시 인식 | `OutPick/Features/Chat/Controllers/ChatViewControllerExtension.swift` | text input·일반 control 제외, `ChatMessageCell` action 예외, simultaneous recognition 정책을 확인한다. |
| retry/media/profile/Lookbook cell action 전달 | `OutPick/Features/Chat/Views/Cell/ChatMessageCell.swift` | `ChatMessageCellCommands` 기반 action 연결을 확인한다. 미사용 long-press delegate는 제거됐다. |
| Profile modal edge dismiss | `OutPick/Features/Profile/Views/UserProfileDetailViewController.swift`, `docs/ai/entrypoints/PROFILE.md` | 35%/900pt/s threshold, 중복 dismiss gate와 기존 Coordinator/transition 재사용을 확인한다. |
| 제거된 custom transition의 대체 경계 | `OutPick/Features/Chat/ChatNavigationController.swift`, `OutPick/Infra/Utility/Transitions/ChatModalTransitionManager.swift` | navigation은 UIKit system pop, Profile modal은 실제 사용 중인 modal transition manager가 담당한다. 삭제된 네 transition 파일을 다시 참조하지 않는다. |

삭제 완료 파일은 `OutPick/Infra/Utility/Transitions/UINavigationController+InteractiveTransition.swift`, `UIViewController+InteractiveTransition.swift`, `PushAnimator.swift`, `PopAnimator.swift`다. 호출자가 없던 전역 custom navigation/interactive transition 경로이며, 현재 navigation과 Profile modal의 실제 owner는 위 표를 따른다.

`RealtimeSocketService`는 새 `SocketIOClient`를 만들 때 lifecycle 3개와 named event 5개 listener를 연결 전에 한 번 등록한다. reconnect나 room consumer 생성·종료 중에는 `off/on`으로 Socket.IO handler 배열을 변경하지 않으며, listener lifetime은 Socket client lifetime과 같다. consumer가 없는 메시지는 actor의 room session lookup에서 drop한다. Socket.IO raw logger는 인증 payload 노출을 막기 위해 사용하지 않는다. 관련 안정화 설계와 반복 reconnect gate는 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-ios-socket-stabilization.md`를 따른다.

room join의 단일 owner는 `RealtimeSocketService`의 `RealtimeRoomJoinState`다. runtime rejoin, background Banner session과 visible strict session이 같은 room join attempt/ACK에 합류하며 reconnect에서는 confirmed membership만 무효화하고 desired joined room은 유지한다. Socket client 교체 시 generation이 다른 이전 client의 connect/disconnect/error/room-close callback은 무시한다. `NO ACK`는 recoverable timeout, 명시적인 room/access 거부 ACK는 terminal join 오류로 분리한다.

`socket-message-dedupe-hardening` Phase 1~3에서 `messageDeliverySingleFlight`가 `kind + roomID + messageID` 단위 instance 내부 owner/follower Promise를 소유한다. `sequenceStore.allocateSeqAndPersist`는 Firestore transaction 결과를 `{ seq, created }`로 반환하고 기존 message는 다시 쓰지 않는다. text/Lookbook/image/video handler는 요청별 보호 검증 후 이 경계에 참여하며 `created: true` winner만 Socket emit과 FCM push를 수행한다. media 완료 retry는 저장된 senderUID, media 종류와 attachment path가 현재 요청과 일치할 때만 기존 seq를 duplicate ACK한다.

`Rooms.lastMessage`, `lastMessageAt`, `lastMessageSeq` 갱신의 단일 소유자는 `sequenceStore.allocateSeqAndPersist` transaction이다. iOS `RealtimeSocketService`는 성공 또는 duplicate ACK 뒤에 room summary를 직접 쓰지 않는다. 따라서 새 메시지 B가 확정된 뒤 오래된 메시지 A를 동일 ID로 retry해도 A의 client timestamp/preview가 B의 room summary를 덮어쓰지 않는다.

`BannerManager`는 참여중 방의 background stream에서 high watermark보다 큰 seq만 즉시 받고, visible 방이면 UI만 생략한다. 모든 accepted event는 `ChatRoomReadStateStore.seedIncomingMessage(_:)`와 `FirebaseChatRoomRepository.applyLocalIncomingMessagePreview(_:)`를 거쳐 목록 metadata를 갱신한다. UI는 단일 FIFO로 5개 outstanding까지만 개별 보관하고 초과분은 단일 summary로 합친다.

background session open이 `NO ACK`·disconnect 등 recoverable 오류로 실패하면 `BannerSubscriptionRetryPolicy`의 0.5초 시작·최대 8초 capped exponential backoff로 같은 room subscription을 유지한다. room_not_found/access rejection 같은 terminal join 오류와 leave/close/logout cancellation에서는 재구독하지 않는다. session open 실패로 만들어진 consumer는 즉시 정리한다.

reconnect는 캐시 token 재사용 대신 Firebase ID token을 강제 갱신하고 새 `SocketIOClient` generation을 만든다. network 복구 뒤 confirmed membership을 다시 join하고 visible strict actor는 마지막 release 다음 seq부터 감사를 시작한다. 2026-07-17 셀룰러 iPhone 14 단절 QA에서 `680001 → 680004` 누락·중복·미래 realtime이 정상임을 확인했다.

room close observation은 현재 참여 여부가 아니라 실제 Chat route의 생존 기간에 결합한다. 따라서 미참여 미리보기에서 같은 화면으로 참여 전환해도 closure를 받으며, authoritative closure가 observer 등록보다 먼저 도착하면 service가 같은 room create 전까지 상태를 기억해 등록 직후 replay한다. Coordinator는 closure를 받으면 실제 route를 제거하고 service는 join/admission/routing/Banner 상태를 정리해 재구독을 막는다.

`ChatMessageWindowStore`는 older/newer pagination chunk를 합친 뒤 최대 300개 visible message window 전체를 seq 순으로 재구성해 날짜 separator와 read marker를 파생한다. 따라서 같은 날짜가 page/chunk 경계를 가로질러도 `dateSeparator(Date)` identity는 날짜별 한 개만 존재한다.

`ChatReadStateStore`는 persisted/queued/pending 최댓값을 read frontier로 사용한다. 일반 visible candidate는 `contiguousLoadedThroughSeq` 이하에서만 queue하고 explicit latest target만 의도적으로 gap을 건너뛴다. Phase 6-C에서 incremental/final 읽음의 `windowMaxSeq` 입력을 제거했으며 `finalSeqForSessionEnd()`는 실제 frontier만 반환한다.

`ChatLatestMessageJumpView`는 참여 중 Chat 화면에서 새 realtime 메시지가 도착했을 때만 입력창 위에 발신자·한 줄 요약·cache-only 이미지/종류 아이콘·아래 화살표와 loading/VoiceOver 상태를 렌더링한다. 진입 전에 쌓인 unread에는 card를 표시하지 않고 initial unread anchor부터 읽는다. `ChatUnreadCatchUpState`는 realtime `ChatMessage.senderNickname + previewTextForRoomList`로 현재 preview 1개와 탭 중 고정 target/generation/loading을 소유하며 payload에 sender 정보가 없을 때만 `새 메시지`로 fallback한다. `ChatViewController`는 최신 realtime마다 cancellable 3초 auto-dismiss task를 다시 시작하고 target 일치 시 읽음 변경 없이 preview만 제거한다. diffable snapshot completion 뒤 target item이 실제 visible이면 즉시 제거하며 route/search 종료에서도 transient preview와 task를 정리하므로 pop/re-entry에서 복원되지 않는다.

최신 이동은 `ChatViewController`가 기존 `ChatMessageWindowStore`, diffable snapshot과 content offset을 백업한 뒤 bounded target window를 적용한다. snapshot completion 후 target item의 실제 layout 가시성이 확인되어야 `ChatRoomViewModel.completeLatestJump`가 explicit frontier를 승인한다. 승인 직후 pending frontier를 `persistExplicitLatestJumpForCurrentUser()`로 await 저장하며 server 성공 뒤에만 local/shared flushed mark를 적용한다. 실패 pending은 route 종료/background final flush 재시도에 남는다. 실패·취소·stale completion은 이전 window/offset/frontier로 복구하고, 이동 중 target보다 높은 realtime seq는 완료 뒤 새 preview로 남긴다. 일반 스크롤 읽음은 settled visible max와 `ChatMessageWindowStore.highestContiguousSeq(after:)` 조합만 사용하며 search window에서는 보고하지 않는다.

Explicit read 진단은 `ChatRoomViewModel.persistExplicitLatestJumpForCurrentUser()`의 저장 직전 상태, `UserProfileRepository.updateLastReadSeq` Firestore transaction의 `current/requested/next/didWrite`, `.server` 강제 재조회 결과를 `[ChatReadPersistence]` 로그로 연결한다. room/user 식별자는 마스킹한다. `DefaultChatInitialLoadUseCase`는 재진입의 `lastRead/latest/openMode`도 기록한다. 2026-07-17 실제 QA에서 `92 → transaction 89/92/92/write=true → authoritative 92`, 재진입 `lastRead=92/latest=92/latestTail`을 확인해 persistence가 정상임을 확정했다.

초기 최신 위치 진입점은 `ChatViewController.setMessageWindow`다. 초기 local→server 전체 window 교체에는 `applySnapshotUsingReloadData`를 사용해 stale cell을 제거하고, snapshot completion 뒤 마지막 message/read marker를 직접 표시한다. estimated-height 셀의 self-sizing으로 content height가 여러 layout pass에 걸쳐 증가하므로 최대 12 frame, 약 0.2초 안에서 height가 2회 연속 안정될 때까지만 위치를 재검증한다. realtime/pagination 증분 snapshot은 기존 diffable apply 경로를 유지한다. 실제 `999999(seq=92)` 재진입 QA에서 최신 target 표시를 확인했다.

`ChatRoomMessageUseCase.loadLatestMessageWindow` → `ChatMessageManager`는 고정 target을 포함하는 서버 권위 tail을 최대 80개로 반환한다. 일반 target은 exclusive `beforeSeq = targetSeq + 1`, `Int64.max`는 latest query를 사용하며 결과는 target 이하·ASC·ID 단일성·target 포함을 검증한다. authoritative initial/history/latest와 realtime incoming은 GRDB 저장 성공 뒤 `ChatOutgoingOutboxUseCase.reconcileServerConfirmedMessages`로 batch outbox 수렴한다. catching-up offscreen event는 UI append와 attachment warmup을 하지 않는다.

`JoinedRoomsViewModel`은 shared read-state stream을 구독해 unread count와 마지막 메시지 summary를 즉시 반영한다. `RoomListsViewModel`은 같은 stream을 신호로 사용해 repository의 cached top rooms snapshot을 다시 발행한다. 단, 앱 재실행/네트워크 재동기화의 authoritative source는 여전히 Firestore 단발 fetch와 pull-to-refresh다.

## 채팅방 Firestore ID 경계와 생성

| 확인할 내용 | 코드 진입점 |
| --- | --- |
| Domain identity와 화면 상태 | `OutPick/Features/Chat/Domain/Models/ChatRoom.swift`; `ChatRoom.id: String`이 non-optional identity |
| 생성 시 입력 상태 | `OutPick/Features/Chat/Domain/Models/CreateChatRoomInput.swift` |
| Firestore read schema | `OutPick/DB/Firebase/DatabaseManager/DTOs/ChatRoomFirestoreDTO.swift` |
| 핵심 불변식 검증과 write payload | `OutPick/DB/Firebase/DatabaseManager/Mappers/ChatRoomFirestoreMapper.swift` |
| 생성 orchestration과 event | `OutPick/Features/Chat/Domain/UseCases/CreateRoomUseCase.swift` |
| ID 생성과 room/member/joined transaction | `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift` |
| 생성 전용 최소 계약 | `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`의 `CreateRoomRepositoryProtocol` |
| rules 차단 | `firestore.rules`의 `roomCreateHasNoDocumentIDFields`, `roomUpdateDoesNotChangeDocumentIDFields` |
| mapper/UseCase/rules 회귀 | `OutPickTests/ChatRoomFirestoreMapperTests.swift`, `OutPickTests/CreateRoomUseCaseTests.swift`, `firestore-tests/room-document-id.rules.test.mjs` |

채팅방 자기 identity는 `DocumentSnapshot.documentID`만 source로 사용한다. Mapper는 document ID, `roomName`, `creatorUID`, `createdAt`을 핵심 불변식으로 검증하고 부가 필드는 legacy 기본값을 허용한다. 새 방은 `Rooms/{roomID}`, `Rooms/{roomID}/members/{creatorUID}`, `users/{creatorUID}/joinedRooms/{roomID}`를 단일 transaction으로 생성하며 room payload에 `ID`, `id`, `participantUIDs`를 쓰지 않는다.

2026-07-14 운영 rules 배포와 기존 Rooms 4건의 uppercase `ID` cleanup을 완료했다. 사후 감사 기준 `Rooms.ID`/`Rooms.id` 보유 문서는 0건이며 방 4개와 핵심 불변식은 유지됐다.

## Socket candidate retry QA

- `RealtimeSocketService.swift`의 `SocketDebugQAConfiguration`은 DEBUG build에서만 launch environment로 Socket URL을 교체한다.
- `OUTPICK_DEBUG_SOCKET_URL`은 `http`/`https`와 host가 유효할 때만 production URL을 대체한다.
- `OUTPICK_DEBUG_DROP_FIRST_MESSAGE_ACK_KIND`는 `text,lookbook,images,video` 또는 `all`을 받아 message ID별 첫 성공 ACK만 결과 불명 실패로 바꾼다.
- 2026-07-15 candidate revision `outpick-socket-dedupe0715`은 운영 traffic 0%, tag `dedupe-qa`로 배포했다. 운영 revision `outpick-socket-00006-k8k`는 100%를 유지한다.
- 실제 text QA에서 서버는 동일 ID retry를 기존 `seq=15`의 duplicate 성공으로 처리하고 Firestore document와 수신 room preview를 한 건으로 유지했다.
- 실제 Lookbook/image/video QA에서도 동일 ID retry가 각각 기존 seq의 duplicate 성공으로 수렴했고 Firestore message document는 한 건으로 유지됐다.
- 최신 video B(`seq=21`) 뒤 오래된 image A(`seq=20`)를 retry한 회귀 QA에서 A는 발신 성공으로 수렴했지만 room summary와 수신 목록 preview는 B의 `[동영상]`, `lastMessageSeq=21`, 기존 `lastMessageAt`을 유지했다.
- 실제 transport 실패 text는 Firestore 미생성·발신 `seq=0/isFailed=1`·outbox failed 상태를 확인한 뒤 앱 재연결과 같은 ID retry로 `seq=22`에 성공했다. Firestore 한 문서, 발신 outbox 삭제와 수신 room preview 한 건으로 수렴해 2026-07-16 task를 종료했다.
- `ChatMessageSendReceipt`와 `ChatOutgoingMessageReceiptMerger`가 text/Lookbook/images/video ACK의 `messageID/seq/duplicate`를 공통 계약으로 소비한다.
- `ChatViewController.reconcileServerConfirmedOutgoingMessage`는 matching optimistic message의 실패 상태와 seq/attachment를 갱신하고 GRDB 저장·outbox 정리를 완료한다.
- Lookbook share는 결과 불명 실패 뒤 같은 방에서 최초 message ID를 재사용한다.
- 재검증 text `messageID=9B79F1C2-E3BC-431A-AF3E-D4C0D50C8B4E`, `seq=17`은 같은 ID retry 뒤 발신 실패 아이콘이 사라지고 수신 room preview가 한 건으로 유지됐다.

## 방 정보 수정 반영

- 설정 화면: `OutPick/Features/Chat/Controllers/ChatRoomSettingViewController.swift`
- 수정 UseCase: `OutPick/Features/Chat/Domain/UseCases/RoomEditUseCase.swift`
- 화면 라우팅/이벤트: `OutPick/Features/Chat/ChatCoordinator.swift`
- Chat navigation edge-pop: `OutPick/Features/Chat/ChatNavigationController.swift`
- 현재 채팅 화면 반영: `OutPick/Features/Chat/Controllers/ChatViewController.swift`

방장 사용자가 방 정보를 수정하면 Firestore room document listener가 아니라 설정 화면 완료 콜백과 Coordinator 이벤트로 현재 채팅 화면의 메모리 room snapshot을 갱신한다. `ChatViewController.applyUpdatedRoom(_:)`가 navigation title, room diff, ViewModel room snapshot 갱신을 담당한다.

## 프로필 표시와 참여자 캐시

- 채팅의 사용자 식별 key는 Firebase Auth UID 기반 `canonicalUserID`다.
- `Rooms.creatorUID`, `Messages.senderUID`, `Rooms/{roomID}/members/{uid}` 문서 ID, `users/{uid}/joinedRooms/{roomID}` owner 경로는 같은 canonical user ID를 저장한다.
- `Rooms.participantUIDs`는 legacy cleanup 대상이며 새 membership source로 사용하지 않는다.
- 참여자 프로필은 `users/{canonicalUserID}` 직접 조회로 가져오며, 이메일/provider field fallback query는 사용하지 않는다.
- 현재 GRDB local display cache는 `LocalChatUser.userID`, `RoomProfileDisplayCache.userID` 기준으로 canonical user ID를 저장한다.
- `chat-legacy-identity-naming`에서 Swift/API와 물리 GRDB table/column을 `userID` 기준으로 정리했다.
- 문서상 `userID == canonicalUserID == Firebase Auth uid`로 고정한다.
- legacy `userProfile`/`roomParticipant` fallback은 제거한다.
- 앱이 아직 TestFlight/App Store 등으로 배포되지 않았으므로 신규 legacy table compatibility는 만들지 않는다. 단, migration fixture의 `chatMessage.senderID NOT NULL` 잔존 오류는 `ChatMessageSenderUIDSchemaRebuilder`를 사용하는 `rebuildChatMessageSenderUIDSchema` migration으로 현재 `senderUID` schema로 재작성한다.
- GRDB `RoomMember` table/model/migration은 제거했다. local membership replica는 유지하지 않는다.
- 현재 local persistence는 `OutPick/Features/Chat/Persistence/`의 소비자별 Protocol과 `ChatPersistenceProvider`, `OutPick/DB/GRDB/Stores/`의 기능별 Store를 사용한다. `AppDatabase`는 pool/migration만 소유하고 Store가 message/FTS/media, LRU, cleanup transaction을 소유한다. 구현 결과와 테스트 범위는 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-3-grdb.md`, `phase-3-grdb-tests.md`를 따른다.
- Profile sync manager: `OutPick/Features/Chat/Managers/Implementations/ChatProfileSyncManager.swift`
  - 메시지 발신자 UID 목록을 batch fetch하고 local user cache를 refresh한다.
  - 프로필 문서 listener/Combine publisher 경로는 사용하지 않는다.
  - mutable cache/remote refresh/GRDB upsert는 actor가 소유하고, UI 동기 read는 MainActor snapshot만 읽는다.
  - snapshot miss 시 GRDB를 즉시 읽지 않으며, refresh 완료 후 변경 senderUID의 현재 메시지 item을 reconfigure한다.
- Profile sync protocol: `OutPick/Features/Chat/Managers/Protocols/ChatProfileSyncManaging.swift`
  - 채팅 진입/메시지 ingest 시 필요한 refresh 계약을 확인한다.
- Participants use case: `OutPick/Features/Chat/Domain/UseCases/LoadChatRoomParticipantsUseCase.swift`
  - 설정 화면 참여자 표시용 remote members pagination과 profile batch fetch 흐름을 확인한다.

## 대형 Membership 전환

- 설계 문서: `docs/ai/tasks/chat-membership-model-transition/design.md`
- 결정 문서: `docs/ai/tasks/chat-membership-model-transition/decisions.md`
- 현재 membership source: `Rooms/{roomID}/members/{uid}`
- legacy cleanup 대상: `Rooms.participantUIDs`, `users.{uid}.joinedRooms` 배열, `users/{uid}/roomStates/{roomID}`
- member doc은 현재 참여자만 존재하며, 방을 나가면 hard delete한다.
- 설정 화면 참여자 목록은 `Rooms/{roomID}/members`를 member documentID 기준 stable order로 pagination한다.
- 설정 화면 참여자 목록은 GRDB/local member cache를 source로 사용하지 않는다.
- GRDB/local profile cache는 최근 메시지 sender nickname/avatar 표시를 위한 bounded cache로 제한한다.
- `LocalChatUser` 전역 캐시 + `RoomProfileDisplayCache(roomID, userID)` 방별 bounded 관계 테이블을 사용한다.
- `RoomProfileDisplayCache`는 방별 최근 메시지 sender 표시 관계만 관리하고, 설정 화면 전체 참여자 목록 source로 사용하지 않는다.
- 메시지 sender cache는 room당 20명 LRU eviction을 사용하고 time-based TTL은 두지 않는다.
- 비참여 preview read 정책은 유지하되, 메시지 전송/media write/설정/참여자 전용 action은 member doc 기준으로 제한한다.
- 방장이 방을 나가면 방 닫기 semantics로 처리하고, Firestore `Rooms/{roomID}` 및 하위 collection과 Storage `rooms/{roomID}/` prefix를 cleanup한다.
- close cleanup은 `participantUIDs` 배열에 의존하지 않고 `members`/joined room projection 기반으로 page 단위 처리한다.
- close cleanup은 별도 job 문서를 만들지 않고 즉시 성공/실패 응답으로 처리한다. 실패 시 화면은 방 나가기 실패를 즉시 피드백하고 사용자가 재시도한다.
- 방장 전용 action의 최종 권한은 `Rooms.creatorUID` 기준으로 판단한다.
- 2026-07-03 Socket Cloud Run, Firestore rules, Functions 운영 배포를 완료했다.
- `firestore:indexes` 운영 배포와 legacy participant index 삭제는 2026-07-03 완료했다.
- 확인 완료: 설정 화면 참여자 목록은 실제 코드에서 GRDB 전체 member cache가 아니라 members pagination만 source로 사용한다.
