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

채팅방 입력창 외 영역 탭 시 키보드 dismiss는 기존 attachment close tap 흐름과 함께 `KeyboardDismissSupport.installKeyboardDismissTapGesture()`로 보강한다.

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
- 앱 실행 중 방 밖 메시지 banner: `OutPick/Infra/Banner/BannerManager.swift`
- 전체 방 목록 preview cache: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
- 참여중 목록 즉시 반영: `OutPick/Features/Chat/ViewModels/JoinedRoomsViewModel.swift`
- 전체 방 목록 즉시 반영: `OutPick/Features/Chat/ViewModels/RoomListsViewModel.swift`

채팅방 화면을 보고 있을 때는 `ChatViewController`가 `RealtimeSocketService.openRoomSession(for:)`로 room join ACK를 받은 뒤 메시지 stream을 구독한다. 수신 메시지는 ViewModel/GRDB 저장 경로를 거쳐 현재 화면에 반영된다.

`ChatRoomSessionActor`는 Socket에서 decode한 메시지를 consumer에게 fan-out하기 전에 방별 최근 message ID 300개로 first-wins 중복 제거한다. 같은 ID·다른 seq도 첫 event를 유지하며, actor가 마지막 consumer와 함께 제거되면 dedupe state도 해제된다. 로컬 실패 메시지 publish는 이 ingress state에 기록하지 않아 같은 ID의 후속 서버 확인 event가 정상 전달된다. `BannerManager`는 별도 recent-ID cache를 두지 않고 같은 actor stream을 사용하며, `ChatMessageWindowStore`와 GRDB upsert는 300개 범위 밖 재수신의 최종 수렴 장치다.

`RealtimeSocketService`는 새 `SocketIOClient`를 만들 때 lifecycle 3개와 named event 5개 listener를 연결 전에 한 번 등록한다. reconnect나 room consumer 생성·종료 중에는 `off/on`으로 Socket.IO handler 배열을 변경하지 않으며, listener lifetime은 Socket client lifetime과 같다. consumer가 없는 메시지는 actor의 room session lookup에서 drop한다. Socket.IO raw logger는 인증 payload 노출을 막기 위해 사용하지 않는다. 관련 안정화 설계와 반복 reconnect gate는 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-ios-socket-stabilization.md`를 따른다.

`socket-message-dedupe-hardening` Phase 1~3에서 `messageDeliverySingleFlight`가 `kind + roomID + messageID` 단위 instance 내부 owner/follower Promise를 소유한다. `sequenceStore.allocateSeqAndPersist`는 Firestore transaction 결과를 `{ seq, created }`로 반환하고 기존 message는 다시 쓰지 않는다. text/Lookbook/image/video handler는 요청별 보호 검증 후 이 경계에 참여하며 `created: true` winner만 Socket emit과 FCM push를 수행한다. media 완료 retry는 저장된 senderUID, media 종류와 attachment path가 현재 요청과 일치할 때만 기존 seq를 duplicate ACK한다.

`Rooms.lastMessage`, `lastMessageAt`, `lastMessageSeq` 갱신의 단일 소유자는 `sequenceStore.allocateSeqAndPersist` transaction이다. iOS `RealtimeSocketService`는 성공 또는 duplicate ACK 뒤에 room summary를 직접 쓰지 않는다. 따라서 새 메시지 B가 확정된 뒤 오래된 메시지 A를 동일 ID로 retry해도 A의 client timestamp/preview가 B의 room summary를 덮어쓰지 않는다.

채팅방 화면을 보고 있지 않을 때는 `BannerManager`가 참여중 방 socket stream을 통해 메시지를 받고 banner를 표시한다. 동시에 `ChatRoomReadStateStore.seedIncomingMessage(_:)`로 `latestSeq`, `latestMessagePreview`, `latestMessageAt`, `lastMessageSenderUID`를 갱신하고, `FirebaseChatRoomRepository.applyLocalIncomingMessagePreview(_:)`로 전체 방 목록 preview cache를 갱신한다.

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
- `ChatMessageSendReceipt`와 `ChatOutgoingMessageReceiptMerger`가 text/Lookbook/images/video ACK의 `messageID/seq/duplicate`를 공통 계약으로 소비한다.
- `ChatViewController.reconcileServerConfirmedOutgoingMessage`는 matching optimistic message의 실패 상태와 seq/attachment를 갱신하고 GRDB 저장·outbox 정리를 완료한다.
- Lookbook share는 결과 불명 실패 뒤 같은 방에서 최초 message ID를 재사용한다.
- 재검증 text `messageID=9B79F1C2-E3BC-431A-AF3E-D4C0D50C8B4E`, `seq=17`은 같은 ID retry 뒤 발신 실패 아이콘이 사라지고 수신 room preview가 한 건으로 유지됐다.

## 방 정보 수정 반영

- 설정 화면: `OutPick/Features/Chat/Controllers/ChatRoomSettingViewController.swift`
- 수정 UseCase: `OutPick/Features/Chat/Domain/UseCases/RoomEditUseCase.swift`
- 화면 라우팅/이벤트: `OutPick/Features/Chat/ChatCoordinator.swift`
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
