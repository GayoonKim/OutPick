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

전체 채팅방 목록은 `Rooms.isClosed == false`, `Rooms.lifecycleStatus == active`, `Rooms.lastMessageAt DESC` 기준으로 활성 방만 가져오고, 각 방의 최근 일반 메시지 3개를 함께 불러와 미리보기로 표시한다. `roomRoleEvent`는 공개 timeline에는 남지만 목록 preview에서는 제외하며, repository가 최신순 문서를 최대 30개 범위에서 추가 탐색해 이전 일반 메시지를 복구한다. 첫 query에 문서가 있었지만 모두 역할 이벤트인 경우 timestamp fallback을 중복 실행하지 않는다. 같은 활성 조건은 `FirebaseChatRoomRepository.activeRoomsQuery()`를 통해 전체 목록, 참여방 ID 일괄 조회, 검색, 방 이름 중복 조회에 공통 적용한다. 메시지 문서의 sender snapshot은 fallback으로 보존하되 `RoomListUseCase`가 `ChatProfileSyncManager`를 통해 sender UID별 최신 `UserPublicProfile`을 화면 표시값에 overlay한다. 프로필 변경 전·후 메시지는 같은 현재 닉네임·아바타를 사용하며 서버 메시지 문서는 다시 쓰지 않는다. 목록 진입과 pull-to-refresh에서 profile을 갱신하고, `RoomListsCollectionViewController`는 최대 30개 방 snapshot을 reload해 동일 room ID의 셀도 다시 구성한다. `ChatCoordinator`는 room/avatar image manager를 목록 화면에 주입한다. `RoomListsCollectionViewController`는 `UICollectionViewDataSourcePrefetching`으로 곧 보일 방의 커버 이미지와 상대방 메시지 `senderAvatarPath`를 미리 캐시에 적재한다. 셀 구성 시 `RoomListCollectionViewCell`은 주입받은 room/avatar image manager를 사용해 캐시를 먼저 확인하고, 없으면 Storage에서 로드한다. 내 메시지 미리보기는 avatar를 숨기고, 상대방 메시지 미리보기만 avatar를 표시한다. 이미지 캐시 정책은 `RoomImageService`/`AvatarImageService`가 `ImageCachePipeline`을 통해 메모리와 전용 디스크 캐시에 저장하는 흐름을 따른다. 컬렉션 뷰 하단은 메인 탭 바와 겹치지 않도록 `view.safeAreaLayoutGuide.bottomAnchor`에 맞춘다.

## 비참여 채팅방 Preview

- 화면: `OutPick/Features/Chat/Controllers/ChatViewController.swift`
- 초기 로드: `OutPick/Features/Chat/Domain/UseCases/ChatInitialLoadUseCase.swift`
- 조립: `OutPick/Features/Chat/ChatContainer.swift`
- Firestore rules: `firestore.rules`

비참여 사용자는 전체 채팅방 목록/검색에서 방을 열어 메시지, 이미지 버블, 비디오 썸네일/메타를 미리 볼 수 있다. 단, 참여 전에는 뒤로가기와 하단 input bar 위치의 참여하기 버튼 외 상호작용을 막는다. 이미지 확대, 동영상 재생, 설정/검색, 메시지 전송/첨부, retry, 메시지 메뉴, 발신자 프로필/룩북 공유 이동 같은 참여자 전용 동작은 `ChatViewController`의 preview guard에서 차단한다.

채팅방은 `ChatViewController.backgroundTapGesture`가 키보드와 attachment 닫기를 담당한다. text input과 일반 `UIControl` superview chain touch는 제외하고, message/media/profile/retry/Lookbook cell tap은 `cancelsTouchesInView = false`와 동시 인식으로 원래 action과 background dismiss를 함께 실행한다. `ChatMessageCell` 내부 retry control도 cell action 우선순위로 허용한다. message long press는 `UICollectionViewDelegate`의 native context menu가 소유해 touch 종료 뒤 메뉴 유지·항목 선택·외부 탭 종료·safe-area 배치를 시스템에 맡기고, announcement long press와 settings dim tap은 각 leaf view가 소유한다. 공통 `KeyboardDismissSupport` 중복 설치는 Chat에서 사용하지 않는다.

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

참여중 채팅방 목록은 Firestore realtime listener를 사용하지 않는다. 화면 진입/앱 재실행 시 단발 fetch로 authoritative snapshot을 만들고, 사용자가 pull-to-refresh로 재동기화한다. 앱 실행 중 참여중 방에 새 메시지가 도착하는 경우에는 `BannerManager`의 socket stream이 `ChatRoomReadStateStore`와 `FirebaseChatRoomRepository`의 local preview cache를 갱신해 목록 화면에 unread/마지막 메시지를 즉시 반영한다. 현재 목록 source는 `users/{uid}/joinedRooms/{roomID}` projection이며, 해당 roomID로 `Rooms` 문서를 `isClosed == false`, `lifecycleStatus == active` 조건과 함께 batch fetch한 뒤 클라이언트에서 `Rooms.lastMessageAt DESC`로 정렬한다.

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
- Phase 6 process-memory burst guard는 `Socket/src/utils/rateLimit.js`가 소유한다. key는 `moderationPrincipalID + roomID + messageKind`, text 12/2초·Lookbook 6/2초·media 4/2초이며 같은 message ID 재시도는 quota를 다시 소비하지 않는다. bucket은 60초 idle TTL, 30초 lazy sweep, 최대 50,000개이고 cap 초과 신규 key는 fail closed한다. auth principal 누락도 fail closed한다.
- 신규 message payload·FCM·iOS `ChatMessage`·GRDB current schema에는 `senderEmail`이 없다. `RealtimeSocketService`는 email을 message event에 싣지 않으며 `GRDBMigrationRegistry`의 `removeSenderEmailFromChatMessage`가 이전 로컬 column을 rebuild로 제거한다.
- 채팅/Lookbook-share 본문은 UTF-8 4,000 bytes 상한이다. `ChatRoomMessageUseCase`와 `ChatUIView`도 같은 byte 기준으로 전송·입력을 막되 길이 counter나 제한 임박 경고는 표시하지 않는다. 텍스트 의미 자동 필터는 두지 않고 신고·차단·방 운영·사후 제재를 사용한다.
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
| Chat route appearance, background dismiss, message native context menu 설치 위치 | `OutPick/Features/Chat/Controllers/ChatViewController.swift` | route 종료/복귀 wiring, root `backgroundTapGesture`, collection view delegate의 `contextMenuConfigurationForItemAt`, settings dim과 announcement gesture owner를 확인한다. |
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

채팅방 자기 identity는 `DocumentSnapshot.documentID`만 source로 사용한다. 앱 내부 owner canonical 이름은 `ownerUID`이며 Mapper는 `ownerUID ?? creatorUID` fallback과 document ID, `roomName`, `createdAt` 핵심 불변식을 검증한다. 최소 지원 버전 cutover 전 새 방 write는 기존 `creatorUID`만 유지한다. 새 방은 Room, owner member, joinedRooms projection을 단일 transaction으로 생성하며 room payload에 `ID`, `id`, `participantUIDs`를 쓰지 않는다.

2026-07-14 운영 rules 배포와 기존 Rooms 4건의 uppercase `ID` cleanup을 완료했다. 사후 감사 기준 `Rooms.ID`/`Rooms.id` 보유 문서는 0건이며 방 4개와 핵심 불변식은 유지됐다.

## Socket candidate retry QA

### Development Socket 환경

- Development Cloud Run: project `outpick-test`, region `asia-northeast3`, service `outpick-socket-development`.
- canonical URL: `https://outpick-socket-development-xyenspjiwa-du.a.run.app`.
- runtime identity: `outpick-socket-development@outpick-test.iam.gserviceaccount.com`.
- Firestore/FCM은 Development project 역할을 사용하고, Storage 객체 권한은 `outpick-test.firebasestorage.app` bucket 하나로 제한한다.
- iOS 연결값은 `Configurations/Development.xcconfig`의 `OUTPICK_SOCKET_URL`이며 Production endpoint fallback은 금지한다.
- handshake는 Firebase ID Token, active account, room access, rate limit을 검증한다. Socket 전용 App Check는 후속 강화 후보다.

- iOS Socket URL은 `AppRuntimeConfiguration`이 검증한 환경별 `OUTPICK_SOCKET_URL`만 사용한다. DEBUG launch environment로 URL을 덮어쓰는 경로는 없다.
- `RealtimeSocketService.swift`의 `SocketDebugQAConfiguration`은 DEBUG build에서 ACK 손실 주입만 담당한다.
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
- 방장 전용 차단 사용자 화면: `OutPick/Features/Chat/Controllers/ChatRoomBannedUsersViewController.swift` + `ViewModels/ChatRoomBannedUsersViewModel.swift`; 설정의 나가기 옆 `차단 사용자` 버튼은 `ChatRoomSettingEvent.requestShowBannedUsers`를 보내고 `ChatCoordinator`가 설정 패널 위에 독립 화면을 full-screen present한다. 독립 화면의 뒤로 가기는 화면만 dismiss해 기존 설정 패널로 복귀한다.
- 수정 UseCase: `OutPick/Features/Chat/Domain/UseCases/RoomEditUseCase.swift`
- 화면 라우팅/이벤트: `OutPick/Features/Chat/ChatCoordinator.swift`
- Chat navigation edge-pop: `OutPick/Features/Chat/ChatNavigationController.swift`
- 현재 채팅 화면 반영: `OutPick/Features/Chat/Controllers/ChatViewController.swift`

방장 사용자가 방 정보를 수정하면 Firestore room document listener가 아니라 설정 화면 완료 콜백과 Coordinator 이벤트로 현재 채팅 화면의 메모리 room snapshot을 갱신한다. `ChatViewController.applyUpdatedRoom(_:)`가 navigation title, room diff, ViewModel room snapshot 갱신을 담당한다.

## 프로필 표시와 참여자 캐시

- 채팅의 사용자 식별 key는 Firebase Auth UID 기반 `canonicalUserID`다.
- `Rooms.ownerUID`/호환 `creatorUID`, `Messages.senderUID`, `Rooms/{roomID}/members/{uid}` 문서 ID, `users/{uid}/joinedRooms/{roomID}` owner 경로는 같은 canonical user ID를 저장한다.
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
- Phase 1 앱 내부 방장 표시는 `ChatRoom.ownerUID` 기준으로 판단한다. 서버 권한은 Phase 2부터 Room owner와 owner member role의 일치를 transaction 안에서 검증한다.
- 2026-07-03 Socket Cloud Run, Firestore rules, Functions 운영 배포를 완료했다.
- `firestore:indexes` 운영 배포와 legacy participant index 삭제는 2026-07-03 완료했다.
- 확인 완료: 설정 화면 참여자 목록은 실제 코드에서 GRDB 전체 member cache가 아니라 members pagination만 source로 사용한다.

## UGC safety와 room moderation v1 계약

- exact contract: `contracts/chat-moderation-v1.json`
- 설계 결정: ADR-024, `docs/ai/tasks/chat-ugc-safety-room-moderation/decisions.md`
- 구현 순서: 같은 task의 `plan.md`
- Phase 0 검증: 같은 task의 `qa-checklist.md`, `progress.md`

### iOS Phase 1 구현 진입점

- principal binding adapter: `CloudFunctionsCurrentUserModerationRepository` → `getMyModerationState`
- bootstrap domain: `CurrentUserModerationState`와 `LoadCurrentUserBootstrapUseCase`
- DI/routing: `AppCompositionRoot` → `AppCoordinator` → `ModerationNoticeViewController`
- suspended는 account/profile Firestore read 전에 차단하고 계정 삭제·로그아웃을 제공한다. restricted 기존 계정은 main read 흐름을 유지하되 서버 write capability와 안내를 적용한다.

### iOS Phase 2 구현 진입점

- 신고 모델·명령·접수 결과: `OutPick/Features/Chat/Domain/Models/ChatModerationReport.swift`
- 사용자·방 신고 callable adapter: `OutPick/Features/Chat/Repositories/ChatModerationReportingRepository.swift`
- 앱 입력 경계: `OutPick/Features/Chat/Domain/UseCases/SubmitChatModerationReportUseCase.swift`
- Phase 2는 후속 화면이 의존할 thin contract만 추가했다. 화면·ViewModel·Coordinator·Container 연결은 Phase 8 전까지 추가하지 않는다.

### Phase 3 iOS 삭제·폐쇄 진입점

- 서버 권위 삭제/방장 종료/종료 확인 callable: `ChatModerationLifecycleRepository.swift`.
- 메시지 삭제: `ChatRoomViewModel` → `ChatRoomMessageUseCase` → `ChatMessageManager` → `deleteChatMessage`; 성공 뒤 GRDB tombstone·FTS/media local cleanup을 적용한다.
- 방장 폐쇄: `ChatRoomSettingViewModel` → `ChatRoomExitUseCase` → `DefaultChatRoomExitRepository`; 방장은 `closeOwnedChatRoom`, 일반 member는 기존 Socket leave를 사용한다.
- Phase 3.1 종료 lifecycle: `FirebaseChatRoomRepository.fetchJoinedRoomList`가 활성 방 일괄 조회에서 빠진 ID의 공용 `Rooms/{roomID}` tombstone을 단건 복원한다. 목록 cell은 별도 종료 배지·색·마지막 메시지 문구를 추가하지 않고, 행 선택 시 `JoinedRoomsViewController`가 방 이름을 포함한 확인 알림을 표시한다.
- 오프라인 종료 확인: `JoinedRoomsViewModel.acknowledgeClosedRoom`은 확인 탭 즉시 종료 행·unread·notice를 optimistic 제거하고 `acknowledgeRoomClosure`를 비동기로 기다린다. 확인 중 같은 세션의 stale 참여방 조회가 와도 종료 행을 다시 넣지 않으며, 서버 확인이 실패하면 제거 전 상태를 복원해 오류 안내 후 재시도할 수 있게 한다.
- 확인 처리: `JoinedRoomsViewModel` → `ChatRoomClosureAcknowledgementUseCase` → `acknowledgeRoomClosure` callable → `DefaultChatRoomLocalExitCleaner` 순서로 본인 membership projection과 로컬 상태를 정리한다. 기존 `roomClosureNotices` 읽기는 Production legacy 문서 자연 만료 기간만 호환한다.
- 실시간 종료: Socket의 `roomClosureWatcher`만 cleanup job을 관찰해 `room:closed`를 발행한다. `RealtimeSocketService`는 같은 room의 권위 종료를 최초 한 번만 `RealtimeRoomClosureEvent` → `SocketChatRoomRuntimeRepository` → `ChatRoomRuntimeUseCase` → `ChatRoomViewModel` → `ChatCoordinator.handleRoomClosure`로 전달하고, Coordinator도 같은 room 안내를 한 번만 표시한다. 종료 유형 fallback은 중복 본문 없이 제목만 표시한다. 참여자가 확인하면 서버 acknowledgement 완료를 기다리지 않고 Coordinator가 현재 채팅 route를 먼저 제거해 원래 목록으로 복귀한다. 이때 retained `RoomListsCollectionViewController`/`JoinedRoomsViewController`는 `ChatRoomClosureListUpdating`으로 해당 room을 즉시 제거하고, `JoinedRoomsViewModel`은 같은 세션의 stale fetch가 종료 room을 복원하지 못하게 막는다. 확인 API는 백그라운드에서 멱등 처리하며 자기 방 삭제 creator는 안내 없이 같은 route·목록 정리 흐름을 사용한다.
- 현재 방 배너 억제: `ChatViewController.viewWillAppear/viewWillDisappear`가 `ChatRoomViewModel` → `ChatRoomRuntimeUseCase` → `DefaultChatRoomVisibilityRuntimeManager`를 동기 호출해 화면 수명주기 순서대로 `BannerManager` visible room을 갱신한다. Presence 원격 갱신만 별도 비동기 작업으로 수행한다.

### Phase 4 iOS 구현 진입점

- 신고·삭제 native context menu: `ChatMessageActionPolicy.swift` → `ChatRoomViewModel` → `ChatViewController.collectionView(_:contextMenuConfigurationForItemAt:point:)` → `ChatCoordinator`
- 방 신고·내보내기·ban 해제: `ChatRoomSettingViewController`/`ChatRoomBannedUsersViewModel` → moderation UseCase/Repository → `ChatCoordinator`
- 방장 내보내기 진입은 다른 사용자의 메시지 long press `내보내기`와 설정 참여자 행의 별도 `…` 버튼이다. 참여자 행 자체 탭은 권한과 무관하게 프로필을 연다. 사유 enum은 `ChatRoomMemberRemovalReason` 하나를 공유한다.
- 방장에게만 설정 하단 나가기 옆 `차단 사용자` 버튼을 노출한다. 독립 화면은 `Default_Profile` 기본 이미지와 displayName snapshot·canonical 사유·시각, pagination, 빈 상태, retry와 `해제` 확인을 담당한다. 방 이름이 포함된 부제는 표시하지 않으며 일반 참여자에게는 진입 버튼을 만들지 않는다.
- owner 종료 안내는 `방장이 채팅방을 종료했어요.`로 Repository notice, 실시간 Coordinator alert, 참여방 목록 offline alert에서 동일하게 사용한다.
- 비참여 채팅 화면은 `ChatRoomViewModel.loadMyRoomAccess` → `ChatRoomMemberModerationUseCase` → `CloudFunctionsChatModerationLifecycleRepository.getMyRoomAccess`로 서버 상태를 조회한 뒤 참여 버튼을 표시한다. 앱 진입·foreground에서 재조회하며 별도 Socket 이벤트를 추가하지 않는다. active ban은 `재입장이 제한된 채팅방입니다`, 조회 실패는 `참여 상태 다시 확인`으로 표시하고 실패한 참여 시 기존 메시지 목록을 제거하지 않는다.
- 미디어 전송 실패 안내는 서버 ACK/timeout 원문을 노출하지 않는다. 전송 실패 시 room access를 재확인해 ban이면 `채팅방 참여가 제한되어 전송을 중단했어요.`를 표시하고, 그 외 일반 이미지·동영상 실패는 별도 팝업 없이 실패 버블의 재시도·삭제 액션으로 복구한다.
- 전역 차단 visibility: 계정별 마지막 성공 UID snapshot Repository → 메모리 block Store/UseCase → `RealtimeSocketService` ordering 뒤 admission → `ChatMessageWindowStore`·검색·gallery·reply·사용자 공지·room preview·banner. 차단 성공 전 현재 window와 기존 GRDB/FTS/media 원문은 유지하며 이후 새 admission만 제외한다. 서버 lifecycle system event는 제외하지 않는다.
  - raw pagination cursor와 hidden seq는 계속 전진한다. 한 번의 UI 요청은 최대 3개 원본 page만 스캔해 차단 메시지가 긴 방에서 전체 이력을 한 번에 읽지 않는다.
  - 앱 재실행/목록 bootstrap의 unread는 `ChatVisibleUnreadUseCase`가 joined projection의 `lastReadSeq`부터 fetch 시점의 room `latestSeq`까지 메시지를 page 단위로 조회해 현재 차단 UID·본인·삭제 메시지를 제외한다. `JoinedRoomsViewModel`은 조회 전/실패 시 raw unread를 유지하고 성공 방만 visible unread와 최신 visible preview로 교체한다. 전역 seq와 서버 read frontier는 건드리지 않는다.
  - media index의 nullable `senderUID`는 `addSenderUIDToMediaIndexes` GRDB migration이 `chatMessage`에서 backfill하고, 신규 local/remote media admission은 공용 Store로 필터링한다.
  - 프로필과 참여자 목록은 유지한다. 답장 등 차단 대상 직접 상호작용은 차단자에게만 `먼저 차단을 해제해 주세요`를 표시한다.
  - 차단 해제 목록은 MyPage `BlockedUsersViewController`이며 성공 후 Store/snapshot만 갱신하고 열린 채팅방을 강제 재조회하지 않는다.
- Phase 7 미디어 pending UI: `ChatMediaUploadUseCase`·`ChatPendingMediaUploadStore`가 `waitingForSlot/uploading/queued/processing/failed/expired`와 7일 outbox를 소유하고 서버 ready 뒤 기존 `receiveImages|receiveVideo`로 confirmed message에 수렴한다. `waitingForSlot/uploading/queued/processing`은 로컬 미리보기만 유지하고 진행률·전송 중 표시는 노출하지 않는다. `failed/expired`에서는 미디어를 가리는 overlay나 별도 실패 아이콘 없이 시간 라벨을 숨기고 그 위치에 44pt 터치 영역의 소형 재시도·삭제 아이콘을 제공한다. 수동 재시도는 새 `uploadID`·`clientMutationID`를 사용한다. Phase 7.5 신고 UI는 attachment 선택 없이 해당 메시지 전체가 신고·evidence 대상임을 명시한다.
- Phase 7.5 삭제 동기화 확정 계약은 `tasks/chat-ugc-safety-room-moderation/phase-7-5-design.md`를 따른다. 서버 공통 mutation은 일반·관리자 삭제에서 sender UID·닉네임·아바타·전송 시각·답장 presentation을 보존하고 원문·미디어·검색 데이터만 제거한다. 계정 탈퇴 bulk는 `senderAnonymized=true`, `알 수 없는 사용자`, 전송 시각만 남기고 작성자 식별정보를 제거한다. Room revision·cleanup/outbox를 함께 만들고 Socket watcher가 단건/head-advanced를 대상 room에만 emit한다. iOS 진입점은 `ChatDeletionSyncUseCase.swift` → `ChatDeletionSyncRepository.swift` → `GRDBChatDeletionSyncStore.swift` → `ChatMessageRecordMapper.swift`이며 account+room cursor, `anonymizesSender`를 영속화하는 방 수명 삭제 마커, durable cleanup queue로 누락·비활성·오프라인 상태를 복구한다. 서버가 직접 반환한 tombstone의 같은/더 최신 revision은 legacy marker의 sender 정책을 exact 교정한 뒤 sanitize하며, 오래된 visible payload에는 marker가 계속 우선해 원문 재노출을 막는다. `ChatMessageCell`은 삭제 전용 중앙 행을 만들지 않고 기존 메시지 셀 presentation을 유지한 채 텍스트·이미지·비디오·룩북 본문만 `삭제된 메시지입니다`로 교체한다. `ChatMessage.previewTextForRoomList`도 삭제 상태를 같은 마침표 없는 문구로 정규화한다. 기존 Firestore 삭제 listener는 제거됐다.
- Phase 7.5E 메시지 신고 UI는 `ChatMessageActionPolicy`가 pending·삭제·본인 메시지를 차단한다. 방장은 타인 메시지에서 신고와 삭제를 동시에 사용할 수 있고 native context menu가 신고·삭제·차단·내보내기를 별도 항목으로 제공한다. `ChatViewController`와 신고 가능한 이미지 뷰어는 `ChatCoordinator`의 동일 route를 연다. `ChatMessageReportViewController`는 dark editorial header·scope card·reason card·detail editor·accent CTA를 렌더링하고 detail editor 밖 tap은 control touch를 취소하지 않은 채 키보드만 닫으며 scroll drag도 interactive dismissal을 사용한다. `신고` CTA는 사유 선택 전 비활성이고 선택 뒤 즉시 활성화되며, 제출 중에는 문구를 유지한 채 비활성화만 하고 activity indicator는 표시하지 않는다. ViewModel의 사유 누락·중복 제출 검증도 방어 경계로 유지한다. reason title·symbol은 content size category에 맞춰 다시 구성하되 symbol 크기는 상한을 두고, 안내·placeholder는 multiline, CTA는 최소 높이 기반으로 확장해 최대 Dynamic Type에서도 scroll 접근성을 보장한다. `ChatMessageReportViewModel`은 현재 화면의 transport 오류에서만 reason/detail/UUID를 유지하고 서버 확정 failed에는 새 UUID를 준비한다. 화면 종료 뒤에는 로컬 신고 상태를 보존하지 않으며 callable transaction이 processing 재사용·`alreadyReported`·새 preparation·`messageAlreadyDeleted`를 판정한다. 삭제 선행 결과는 기존 `ChatDeletionSyncUseCase.reconcile`로 즉시 수렴한다.
- 실패 outbox 복원 시 server window 뒤에 과거 날짜의 로컬 실패 메시지가 다시 붙을 수 있다. `ChatMessageWindowStore`의 날짜 구분선 diffable identifier는 `(day, occurrence)`를 사용해 같은 날짜가 비연속으로 반복돼도 유일하게 유지한다. 날짜 표시는 day만 사용하며 occurrence는 UI에 노출하지 않는다.
- local session payload는 `uploadID`, `clientMutationID`, kind, expiry만 저장하고 bearer 성격의 signed URL·required headers는 GRDB에 영속화하지 않는다. terminal 실패·업로드 완료 후 finalize 실패는 session identity도 지운다. `ChatViewController.restoreMediaOutboxIfNeeded`는 이 레코드들을 session 조회 조건에서 제외하고 보존된 local/uploaded retry payload를 `ChatPendingMediaUploadStore.failed`로 복원해 재실행 후에도 시간 위치의 재시도·삭제 액션을 유지한다. `queued/processing/ready`처럼 서버에서 계속 진행 가능한 레코드만 session identity로 status monitoring을 재개한다.
- 재실행 복원은 outbox의 영속화용 `isFailed`가 왼쪽 실패 표시로 노출되지 않도록 network status 조회 전에 local bubble을 silent pending으로 stage하고 셀을 재구성한다. `ChatMediaUploadUseCase.reconcileRestoredMediaProcessing`은 파일 PUT을 자동 재개하지 않고 같은 session identity의 status만 2·4·8초 재확인한다. `queued/processing/ready`면 monitoring으로 복귀하고 계속 `uploading`이거나 조회 오류가 지속되면 cancel 후 session credential을 제거한 수동 재시도·삭제 상태로 닫으며 cancel/ready 경합은 ready를 우선한다.
- 실패 액션은 즉시 실행하지 않는다. 재시도는 `이 메시지를 다시 전송할까요?`와 `취소 / 다시 시도` prominent 확인창, 삭제는 `이 실패 메시지를 삭제할까요? 삭제하면 다시 복구할 수 없어요.`와 `취소 / 삭제` destructive 확인창을 거치며, confirm callback 전에는 pending/outbox/로컬 파일/버블을 변경하지 않는다.

### Phase 7.1 미디어 격리·처리 lifecycle 진입점

- Socket v2 API: `Socket/src/handlers/mediaHandlers.js`의 `chat:mediaPreflight`, `chat:mediaRefreshUploadTargets`, `chat:mediaFinalize`, `chat:mediaProcessingStatus`, `chat:mediaCancel`과 `Socket/src/media/mediaUploadService.js`. iOS Phase 7.3은 이미지·영상 모두 attachment당 단일 source descriptor와 24시간 V4 signed PUT target을 사용한다. refresh는 PUT 응답 유실 시 Storage generation·크기·체크섬으로 완료 source를 한 번 복구하고 미완료 source만 재발급한다. finalize는 source를 직접 검증한 뒤 `queued`까지만 전환해 message/seq/emit/push를 만들지 않는다. `chat:mediaCancel`은 서버 cleanup용 계약으로 남고 전송 중 사용자 취소 UI에서는 노출하지 않는다.
- Storage metadata DI: `Socket/src/app/createProductionDependencies.js`. `CHAT_MEDIA_QUARANTINE_BUCKET`이 없으면 v2만 fail closed하고 기존 v1은 유지한다.
- queue와 execution lifecycle: `functions/src/chat/media/{contracts,functions,orchestrationService}.ts`. queued update가 종류별 Cloud Task를 만들고 private dispatcher가 환경별 고정 `chatMediaProcessingSlots` lease를 얻은 경우에만 실행을 시작한다. 이미지는 private Cloud Run Service의 인증된 동기 요청, 영상은 Cloud Run Job execution을 사용한다. 5분 watchdog은 upload reservation 24시간·processing 6시간·execution lease 만료를 재시도 또는 terminal로 수렴시킨다.
- worker: `tools/chat-media-processing-worker/src/{cloudJob,httpService}.ts`가 Quarantine source를 순차 처리하고 deterministic `display/thumbnail`을 staging한 뒤 같은 lease의 `normalizedManifest`를 기록한다. `httpService.ts`는 이미지 Service의 `POST /process`, `cloudJob.ts`는 영상 Job 환경 계약을 담당한다.
- Rules/index: 전용 bucket source는 `storage.chat-media-quarantine.rules`, 서버 전용 원장·slot deny는 `firestore.rules`, collection-group watchdog과 `MediaUploads.expiresAt` TTL은 `firestore.indexes.json`이다. Development는 Quarantine `outpick-test-chat-media-quarantine`과 일반 media `outpick-test-chat-media`를 target에 연결해 Rules를 배포했고 Production은 변경하지 않았다.

### Phase 7.2 ready·delivery·성공 cleanup 진입점

- ready transaction: `functions/src/chat/media/readyService.ts`, trigger와 cleanup scheduler는 `functions/src/chat/media/functions.ts`. worker lease·manifest·현재 room member/ban을 다시 확인한 뒤 message, room seq/preview, `mediaIndex`, `chatMediaDeliveryJobs`, `MediaUploads.ready`와 execution/principal slot 반환을 한 transaction에서 처리한다. 닉네임·아바타는 ready 시점 `userPublicProfiles/{uid}` 서버 snapshot, 본문은 빈 문자열, `sentAt`은 ready 커밋 시각이다.
- delivery: `Socket/src/media/mediaDeliveryWatcher.js`가 pending/retry/만료 processing job을 60초 lease로 claim하고 기존 `receiveImages|receiveVideo`와 `fanoutChatPush`를 수행한다. 실패는 지수 backoff로 재시도하며 messageID/seq가 at-least-once 중복 제거 key다. `createProductionDependencies.js`가 watcher lifecycle을 조립하고 graceful shutdown에서 listener/timer를 해제한다.
- public/read cleanup: `storage.rules`는 account capability와 공개 v2 message 두 문서만 조회해 visible·미삭제 상태와 `readyAttachmentIDs`가 일치할 때 새 attachment 경로 get을 허용한다. Storage Rules의 Firestore 교차 조회 2문서 한도를 위해 room 조회는 하지 않고 종료 room은 기존 message/content 즉시 cleanup과 재시도로 수렴한다. v2 attachment와 `mediaIndex`는 `bucketOriginal/pathOriginal`, `bucketThumb/pathThumb`을 함께 저장해 실제 bucket을 명시하며, legacy v1만 기본 Firebase bucket fallback을 사용한다. ready는 Quarantine source만, canceled/failed/expired는 source와 orphan ready 객체를 즉시 삭제하고 15분 scheduler가 실패 cleanup을 재시도한다. delivery job과 terminal upload은 7일 TTL이다.
- 2026-08-19 signed PUT cutover revision `outpick-socket-development-00013-muw`(tag `p73-350m-0819`)는 276-byte JPEG 단건과 31,364,213-byte MP4 두 조각 backend E2E, tagged/canonical readiness 200과 ERROR 0건 확인 뒤 Development traffic 100%로 전환했다. E2E에서 확인한 GCS custom metadata의 kebab-case 반환은 `mediaUploadService.js`가 camelCase와 함께 canonical 비교한다. 이전 revision들은 0% rollback으로 보존한다.
- 2026-08-19 단일 source foreground cutover는 worker image `sha256:347fe037…`, image Service `outpick-chat-media-image-service-development-00001-8tg`, 갱신된 video Job, Socket `outpick-socket-development-00015-ruw`(tag `p73-foreground-0819`)와 media Functions 5개까지 Development에 반영했다. Socket tagged readiness 뒤 traffic 100%를 전환했고 `outpick-chat-media-orch-dev@…`에는 image Service 한정 invoker, task 계정에는 재배포 후 dispatcher invoker를 복구했다. 인증 proxy root 200과 배포 후 Socket/Functions ERROR 0을 확인했다. 새 실제 사용자 source core E2E는 iOS QA로 남았으며 Production은 미변경이다.
- 2026-08-27 Phase 7.6 Development rollout에서 deletion watcher 포함 Socket revision `outpick-socket-development-p75-del-0827`, digest `sha256:e3d26a46a75252ae683a14c8f0aa8e9e3cef28e72e019d02abdb080b5e591625`를 0% candidate로 검증했다. tagged readiness 200, 기존 active 계정 인증 handshake와 ERROR 0 뒤 traffic 100%로 전환했고 `00015-ruw`는 0% rollback으로 보존한다. 실제 삭제 E2E는 공동 수동 QA 대상이다.
- 2026-08-20 GIF 실기기 QA에서 sharp 기본 최적화가 연속 중복 50프레임을 2프레임으로 합쳐 exact frame-count 검증이 실패하는 결함을 확인했다. `imageProcessor.ts` GIF 출력에 `keepDuplicateFrames: true`를 적용하고 50프레임·delay·loop 회귀 테스트를 추가했다. Cloud Build `89daa082-3e7b-4e0e-b7b2-b5717b5e19a0` 검증과 runtime image build `d1d238d9-1f96-41ae-bc71-7cf099b20069`가 통과했으며 digest `sha256:056d5106036845e4b129ede29307860e6a59f29ed6857681cbf1caa372eeafa2`를 Development image Service revision `outpick-chat-media-image-service-development-00002-ggv`에만 배포했다. CPU 2·1 GiB·concurrency 1·timeout 3600초·bucket·service account·invoker를 유지한 채 traffic 100%, 인증 proxy root 200, 새 revision ERROR 0건을 확인했다. video Job과 Production은 변경하지 않았으며 같은 GIF 실기기 재QA는 남아 있다.

### Phase 7.3 iOS upload·pending·outbox 진입점

- transport source: `ChatImageTransportSourceNormalizer.swift`가 정적 이미지 orientation·sRGB·metadata 제거, JPEG quality 0.92·PNG 보존·HEIC/HEIF→JPEG와 GIF 원본 보존을 담당한다. `ChatMediaSelectionChunker.swift`가 선택 순서대로 메시지당 30장·합산 150 MiB를 분할한다.
- foreground upload: `ChatMediaForegroundUploadService.swift`가 이미지 또는 350 MiB 이하 MP4 source를 attachment당 하나의 signed PUT target에 직접 전송한다. PUT 실패·응답 유실은 서버 object reconciliation을 한 번 수행한 뒤 로컬 실패로 전환하며, 사용자가 명시적으로 재시도하거나 삭제한다. 앱 종료·방 이탈을 위한 background session 복원과 전송 중 취소 UI는 사용하지 않는다. signed URL과 required headers는 로그와 GRDB 모두에 남기지 않는다.
- 다중 선택·연속 전송: picker는 제한 없이 선택하고 `ChatMediaSelectionChunker`가 선택 순서를 유지한 최대 30장 message들로 나눈다. 분할 자체는 안내하지 않으며 실제 제외 이미지가 있을 때만 제외 안내를 표시한다. 모든 pending 버블·outbox를 먼저 저장하고 feature가 공유하는 `ChatMediaUploadTurnQueue` actor가 이미지 FIFO와 영상 FIFO를 서로 독립적으로 운영한다. 각 kind는 로컬에서 한 upload만 reservation·PUT·finalize·ready monitoring까지 진행하고 terminal 또는 취소 뒤 다음 waiter를 깨우므로 31장뿐 아니라 60장·70장과 연속 picker batch도 빈 slot을 기다린다.
- orchestration: `ChatMediaUploadUseCase.swift` → `ChatMediaMessageSendingRepository.swift` → `RealtimeSocketService.swift`가 v2 preflight/upload/finalize/status/cancel을 수행한다. Socket ACK의 machine-readable `serverErrorCode`를 보존하고 Repository가 `active_upload_limit`을 typed capacity error로 변환하면 UseCase는 같은 `uploadID`·`clientMutationID`로 2·4·8·15·30초 이후 30초 간격을 유지해 재예약한다. 비비용량 오류는 즉시 실패하고 reservation 이후 실패는 server cancel로 정리하며 cancel/ready 경합에서는 ready를 우선한다. `ChatOutgoingOutboxUseCase.swift`와 GRDB migration/store가 reservation·source 경로·processing 상태를 복원하며 보존 파일은 backup 제외와 `completeUntilFirstUserAuthentication` 보호를 적용한다.
- UI: `ChatViewController{,Extension}.swift`와 `ChatMessageCell.swift`는 client 정규화 직후 로컬 미디어 버블을 삽입한다. pending 이미지와 outbox 복원 attachment는 별도 저품질 thumbnail 파일이 아니라 동일한 upload source를 가리키며, `ChatAttachmentImageService`가 렌더링 시 최대 1024px로 메모리 다운샘플링한다. uploading/queued/processing은 같은 버블을 무표시로 유지한다. failed/expired는 미디어 dim/overlay를 만들지 않고 시간 자리를 17pt 재시도·삭제 아이콘으로 교체하며 각 액션의 터치 영역은 44×44pt다. 공용 빨간 실패 아이콘은 텍스트 실패에만 유지한다. 실패 전 활성 pending인 `seq <= 0` 메시지는 long-press 서버 액션을 모두 차단한다. 실제 서버 delivery가 같은 messageID로 도착하면 보이는 성공 전환 없이 pending/outbox만 정리한다.
- v2 message mapping: `ChatMessage.makeAttachment`가 `attachmentID`, `bucketThumb`/`bucketOriginal`, format/animation metadata를 보존하고 `ChatAttachmentImageService`·`ChatVideoAssetService`가 전용 bucket의 `gs://` resource를 사용한다. `ChatMessageMediaAttachmentMappingTests`가 기본 bucket fallback 회귀를 차단한다.
- GIF 표시: `readyService.ts`가 worker `technicalValidationResult`의 검증된 format·frame 수·animation 상태를 확정 message와 `mediaIndex`의 `mediaFormat`·`animated`로 투영한다. `Attachment.isAnimatedGIF`는 `image + gif + animated == true`를 모두 요구하고, `ChatImagePreviewCell`은 정적 JPEG thumbnail 우하단에만 `GIF` badge를 표시한다. `ChatViewController.presentImageViewer`는 해당 page에만 원본 data loader를 연결하며 `SimpleImageViewerVC`의 Kingfisher `AnimatedImageView`가 frame preload 3, 현재 page 단독 재생으로 animation을 제공한다. 2026-08-20 `onChatMediaWorkerCompleted` Development 배포와 iPhone 14 설치 뒤 새 seq 20 GIF의 message/mediaIndex metadata, badge·viewer animation·정적 thumbnail 복귀, cleanup 완료와 처리 구간 ERROR 0건을 확인했다.

### Phase 7.4C-1 메시지 신고 evidence copy·cleanup 진입점

- 신고/evidence 계약과 preparation transaction: `functions/src/moderation/messageEvidence/{contracts,service}.ts`.
- Storage copy/검증: `evidenceCopy.ts` → `evidenceStorage.ts`. ready bucket의 exact message display path·고정 source generation·bytes·message kind별 개수/MIME를 검증하고 `{bundleID}/g{attemptGeneration}/{attachmentID}/display`에 create-if-absent로 복사한다.
- retry/fence: 최초 포함 최대 3회, 1분/2분 backoff, 9분 runtime/12분 lease다. bundle/job/preparation mutation은 `attemptGeneration + leaseToken`, Storage delete는 destination generation과 ownership metadata로 fence한다. acceptance/failure drain은 실행당 최대 30건이다.
- retention cleanup: `evidenceCleanup.ts`가 generation 일치 evidence 객체를 전부 삭제한 뒤 `moderationMessageEvidence/{bundleID}`를 완전 삭제하고 비민감 cleanup receipt만 7일 남긴다.
- 함수 정의: `evidenceFunctions.ts`의 create trigger 2개와 5분 recovery scheduler를 `functions/src/index.ts`가 export한다. `evidenceRuntime.ts`가 환경별 전용 서비스 계정과 maxInstances를 fail-closed로 고정하고, Development 세 Function·bucket/IAM·필수 인덱스 3개·실객체 E2E는 완료했다. Rules·TTL override·관리자 조회·Production 배포는 후속 승인 gate다.
- Development 재현: `functions`에서 `npm run build` 뒤 `node scripts/qa-message-evidence-development.mjs --run-id {격리ID}`를 실행하면 30×5MiB 이미지와 350MiB MP4 fixture를 만들고 copy/acceptance/익명 403/cleanup/잔여 0을 확인한다. 반드시 `outpick-test` 자격 증명으로만 실행한다.
- 검증: `functions/src/moderation/messageEvidence/{contracts,evidenceCopy}.test.ts`, `firestore-tests/moderation-reports.emulator.test.mjs`.

### 서버·데이터 Phase 1 구현 진입점

- Functions: `functions/src/moderation/{contracts,identity,state,functions}.ts`, `functions/src/shared/accountStatus.ts`
- Socket: `Socket/src/moderation/capabilities.js`, auth middleware, user projection watch, message/media/room handlers
- Rules: `firestore.rules`, `storage.rules`의 `moderationAccounts/{uid}` fail-closed read/write 판정과 moderation 내부 collection deny
- tests: Functions moderation/accountStatus, Socket moderation/auth/watch/lifecycle, `firestore-tests/moderation-{capabilities.rules,principal.emulator}.test.mjs`, iOS bootstrap test

### 서버·데이터 Phase 2 구현 진입점

- 사용자 신고: `functions/src/moderation/reports/{contracts,service,functions}.ts`의 `submitUserReport`, `submitRoomReport`.
- 관리자 신고 처리: `functions/src/moderation/admin/{contracts,service,functions}.ts`의 목록·상세·review mutation·계정 제재 callable.
- 감사 idempotency: `functions/src/moderation/audit/contracts.ts`와 append-only `moderationAuditLogs`.
- 사용자 신고는 같은 `clientRequestID`를 rate count 전에 dedupe하고 principal당 UTC 1분 10건의 짧은 burst만 제한한다. 일/대상별 hard cap은 없다.
- server-only rate bucket은 `moderationReportRateLimitBuckets`, `moderationAdminRateLimitBuckets`이며 TTL은 2일이다.
- client direct access 차단은 `firestore.rules`, 관리자 queue composite index와 rate bucket TTL은 `firestore.indexes.json`이 소유한다.

### Phase 5 room ban·owner succession 진입점

- Functions callable: `functions/src/chat/moderation/{roomBanService,functions}.ts`의 `removeRoomMember`, `unbanRoomMember`, `listRoomBans`.
- Functions account sweep: `functions/src/chat/moderation/{roomMembershipSweep,roomMembershipSweepFunctions}.ts`; 계정 삭제는 `functions/src/accountDeletion/cleanup.ts`, 영구 정지는 `functions/src/moderation/admin/service.ts`가 durable job을 시작한다.
- Socket: `Socket/src/rooms/roomAccess.js`의 principal ban admission과 `roomBanWatcher.js`의 대상 연결 강제 퇴장·`room:membership-removed` 발행.
- iOS runtime: `RealtimeSocketListenerBinder` → `RealtimeSocketService` → `ChatRoomRuntimeRepository`/UseCase/ViewModel → `ChatViewController`의 read-only 전환과 room-scoped outbox/upload 취소.
- iOS 방 관리: `ChatRoomSettingViewController`/`ChatRoomBannedUsersViewModel` → `ChatRoomMemberModerationUseCase` → `ChatModerationLifecycleRepository`.
- Rules/index: `firestore.rules`의 ban read deny·membership create 거부, `firestore.indexes.json`의 bans/succession job query와 TTL.
- authoritative identity: 콘텐츠·membership은 UID, 장기 제재·room ban만 `moderationPrincipalID`
- moderator delegation 자동 승계는 `roomMembershipSweep.ts`의 request/generation 또는 state-version fence와 `roomMembershipSweepFunctions.ts`의 Task Queue를 사용한다. 논리 재시도는 최초 포함 4회·총 50초이며 일반 참여자는 후보가 아니다. account deletion finalizer는 resolved job 완료 전 차단되고, 과거 role event 개인정보는 같은 ID의 privacy outbox를 통해 iOS/GRDB에 수렴한다.

### Moderator delegation Phase 2 서버 역할 진입점

- Callable/계약: `functions/src/chat/moderation/{contracts,functions}.ts` → `functions/src/index.ts`의 `assignRoomModerator`, `revokeRoomModerator`, `resignRoomModerator`, `leaveChatRoom`, `transferRoomOwnershipAndLeave`.
- 권한 transaction: `roomRoleService.ts`가 actor capability·membership·owner projection을 검증하고 member/joined role, moderator count, 공개 role event, Socket outbox, 24시간 receipt를 원자 갱신한다. 첫 임명은 누락된 server-only count 문서를 원자 생성한다.
- 기존 제재 확장: `roomBanService.ts`의 remove/list/unban/access와 `service.ts`의 message delete가 현재 owner/moderator matrix를 사용한다. 임명 관리자는 owner·현재 moderator를 제재할 수 없고, 퇴장 작성자의 과거 메시지는 일반 퇴장 사용자 콘텐츠로 취급한다.
- Rules: `firestore.rules`가 owner/role/event/private state 직접 쓰기와 member 직접 삭제를 막고 `lastReadSeq`·`lastReadUnreadMessageSeq`의 단조 증가만 허용한다.
- iOS API adapter: `OutPick/Features/Chat/Repositories/ChatModerationLifecycleRepository.swift`의 `ChatRoomRoleMutationRepositoryProtocol`과 Cloud Functions 구현. Phase 4 화면은 아래 역할 세션을 통해서만 mutation을 노출한다.

### Moderator delegation Phase 3 timeline·Socket·안읽음 진입점

- 일반 text/lookbook message sequence는 `Socket/src/messages/sequenceStore.js`, media ready sequence는 `functions/src/chat/media/readyService.ts`가 `seq + unreadMessageSeq`를 같은 transaction에서 증가시킨다. legacy 일반 message는 `unreadMessageSeq ?? seq`로 읽는다.
- 역할 전달은 `Socket/src/roles/roleEventDeliveryWatcher.js`가 `chatRoleEventDeliveryJobs`를 claim하고 `chat:roomRoleEvent`를 방 전체에 발행한다. success는 즉시 삭제하고 최종 실패만 24시간 TTL을 사용한다.
- iOS ingress는 `RealtimeSocketListenerBinder` → `RealtimeSocketService`의 공통 message admission으로 합쳐 event ID를 Socket/pagination dedupe key로 쓴다.
- timeline 표시는 `ChatViewController` → `RoomRoleEventCollectionViewCell`이며, `ChatMessageActionPolicy`·`BannerManager`·`FirebaseChatRoomRepository`·`GRDBChatMessageStore`가 role event를 action/banner/preview/search/media projection에서 제외한다. `ChatMessageWindowStore`의 `여기까지 읽었어요` 마커도 unread 대상 message만 기준으로 삼아 role event 단독으로는 생성하지 않는다.
- 방장 퇴장 후보 선택은 `ChatRoomSettingViewController`의 큰 page sheet가 담당한다. editorial serif 제목, monospaced eyebrow·순번, 사각 avatar와 accent selection rail을 사용해 앱의 패션 매거진 디자인 언어를 따른다. 후보 셀에는 닉네임만 표시하고 CTA 위 별도 안내 문구는 두지 않는다. 적격 관리자 목록에서 하나를 선택하기 전에는 `넘기기`가 비활성이고, 선택 뒤 활성화한 다음 최종 확인창을 거쳐 `transferRoomOwnershipAndLeave`를 호출한다. 확인 문구는 `방장 권한을 넘긴 뒤 채팅방에서 나가요\n권한을 넘기면 되돌릴 수 없어요`로 마침표 없이 표시한다. 후보가 없으면 `방장 권한을 넘길 관리자가 없어요\n나가면 방이 종료돼요`를 안내한다.
- 설정 사진/동영상은 `ChatRoomMediaIndexEntry`가 `bucketThumb/bucketOriginal + pathThumb/pathOriginal`을 `gs://bucket/path`로 해석하고 `LoadChatRoomMediaUseCase`가 이 resource path를 thumbnail/original loader에 전달한다. 출시 이력이 없는 신규 스키마이므로 로컬 backfill 대신 Development 채팅 데이터를 초기화하고 새 문서만 이 계약으로 생성한다.
- 읽음 경계는 `ChatReadStateStore`·`ChatRoomReadStateStore`·`ChatUnreadCatchUpState`·`ChatRoomViewModel`이 timeline/unread frontier를 분리하고 `UserProfileRepository.updateReadFrontier`가 두 값을 단조 증가시킨다.

### Moderator delegation Phase 4 iOS 역할 세션·화면 진입점

- `ChatRoomRoleSession`은 구독 generation으로 cancel 이전의 늦은 snapshot/error를 차단한다. stop/background에서 권한 source를 cache로 낮추고 foreground 새 구독은 최신 server 확인 뒤에만 운영 권한을 활성화한다. `ChatMessage`의 Dictionary/Codable 두 디코더 모두 일반 message의 `unreadMessageSeq ?? seq`를 복원하고 role event는 unread 순번을 갖지 않는다.

- 단일 역할 관찰: `FirestoreChatRoomRoleRepository` → `ObserveChatRoomRoleUseCase` → `ChatRoomRoleSession`. `ChatContainer`가 방마다 한 세션을 만들고 `ChatRoomViewModel`·`ChatRoomSettingViewModel`이 공유한다. cache는 표시 전용이며 server/mutation 상태에서만 관리가 가능하다.
- 참여자 조회·정렬: `FirebaseChatRoomRepository.fetchPinnedRoomMembers/fetchRoomMembersPage` → `LoadChatRoomParticipantsUseCase` → `ChatRoomParticipantOrdering` → `ParticipantsSectionParticipantCell`/`ParticipantListCell`. 순서는 나→방장→관리자→일반 참여자이며 pinned/page 중복을 제거한다. 참여자 행과 section은 Dynamic Type self-sizing이고, 중첩 collection은 참여자 수 기반 초기 예상 높이 뒤 실제 content size로 교정한다.
- 역할 mutation 화면: `ChatRoomSettingViewController` → `ChatRoomSettingViewModel` → `ManageChatRoomRoleUseCase` → `ChatRoomRoleMutationRepositoryProtocol`. 방장 이전·종료는 `ChatRoomExitUseCase`와 `ChatCoordinator.handleRoomExit`로 수렴한다.
- 현재 역할 projection 삭제: `ChatViewController.bindCurrentRoomRoleSession`이 설정을 닫고 pending 전송을 취소한 뒤 `getMyRoomAccess`로 banned/joinable 상태를 재확인한다.
- 메시지 운영: 임명 관리자가 context menu를 열 때 `FirestoreChatRoomRoleRepository.fetchMemberRole`로 작성자 문서 한 건만 서버 조회한다. member 또는 문서가 없는 퇴장 작성자만 운영 삭제·내보내기를 노출한다.

### 고정 사용자 동작

- 신고 대상은 사용자·방·메시지다. 기존 사용자/방 신고는 별도 case를 유지하고, Phase 7.4 메시지 long press 신고는 canonical `roomID + messageID` incident와 메시지 전체 evidence bundle을 만든다. attachment 선택·동영상 timestamp·신고자 개인 자동 숨김은 사용하지 않는다.
- 차단은 blocked-by-me 단방향 콘텐츠 visibility다. 채팅 current window는 유지하고 이후 새 admission만 제외하며 hidden seq와 원본 pagination cursor는 소비한다. 기존 로컬 원문은 소급 삭제하지 않고 새 UI admission에서 필터링한다. 룩북 댓글·답글은 차단 성공 즉시 숨긴다.
- 2026-08-11 Phase 4 Production은 Functions `blockUser`/`unblockUser`와 Socket revision `outpick-socket-p4-block-0811`을 반영했다. 두 계정 QA에서 current-window 유지, 차단 후 live admission 제외, 참여자 유지, unblock 후 재진입 복원과 future live 수신을 확인했다. 실제 기기 background push는 추가 QA 항목이다.
- 2026-08-11~12 Production 앱 종료 혼합 unread QA에서 `lastReadSeq=1`, 차단 `seq=2`, 비차단 `seq=3` 조건으로 재실행 목록의 visible unread 1·비차단 preview와 재진입 차단 메시지 제외를 확인했다. Production 제3자 계정을 추가하지 않고 QA 방 한정 합성 발신자를 사용했으며 방·projection·차단 relation·Storage를 잔존 0건으로 정리했다.
- message delete는 seq tombstone을 유지하고 공개 payload·projection·Storage를 서버 cleanup으로 정리한다.
- room ban은 활성 방 읽기 visibility를 바꾸지 않고 membership 제거와 같은 provider 재가입·참여자 전용 Socket/message/media write만 막는다. 내보내기 뒤 현재 화면은 기존 읽기 cache를 유지한 non-member 상태가 되고 pending outbox·미완료 upload만 취소한다. unban은 membership을 자동 복원하지 않는다.
- creator 계정 삭제 최종 확정·영구 정지는 공용 durable membership sweep과 방별 succession transaction을 사용한다. 영구 정지는 모든 room membership을 제거하고 해제 뒤 자동 복구하지 않으며, 승계 중 일반 채팅은 유지하되 기존 owner capability는 즉시 차단한다.
- Phase 7 구현 시 기술 검증·metadata 제거 중 미디어는 공개되지 않고 seq도 없다. ready transaction에서만 message와 seq가 생기며, 유해성 의미 판정은 수행하지 않는다.
