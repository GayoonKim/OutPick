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
- Room 저장 인덱스 반영: `OutPick/Features/Chat/Domain/Models/ChatRoom.swift`
- Firestore indexes: `firestore.indexes.json`
- Firestore room/message/media preview read rules: `firestore.rules`

방 목록 검색은 방 이름과 방 설명에서 자동 생성한 검색 token을 기준으로 동작한다. 입력과 상태 흐름은 `RoomSearchViewModel`의 Combine state publisher가 소유하고, 방 선택 같은 단발 라우팅 이벤트는 `RoomSearchViewController`의 클로저를 유지한다.

## 비참여 채팅방 Preview

- 화면: `OutPick/Features/Chat/Controllers/ChatViewController.swift`
- 초기 로드: `OutPick/Features/Chat/Domain/UseCases/ChatInitialLoadUseCase.swift`
- 조립: `OutPick/Features/Chat/ChatContainer.swift`
- Firestore rules: `firestore.rules`

비참여 사용자는 전체 채팅방 목록/검색에서 방을 열어 메시지, 이미지 버블, 비디오 썸네일/메타를 미리 볼 수 있다. 단, 참여 전에는 뒤로가기와 하단 input bar 위치의 참여하기 버튼 외 상호작용을 막는다. 이미지 확대, 동영상 재생, 설정/검색, 메시지 전송/첨부, retry, 메시지 메뉴, 발신자 프로필/룩북 공유 이동 같은 참여자 전용 동작은 `ChatViewController`의 preview guard에서 차단한다.

## 참여중 채팅방 목록

- 화면: `OutPick/Features/Chat/Controllers/JoinedRoomsViewController.swift`
- ViewModel: `OutPick/Features/Chat/ViewModels/JoinedRoomsViewModel.swift`
- UseCase: `OutPick/Features/Chat/Domain/UseCases/JoinedRoomsUseCase.swift`
- Repository protocol: `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`
- Repository implementation: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
- Firestore indexes: `firestore.indexes.json`

참여중 채팅방 목록은 Firestore realtime listener를 사용하지 않는다. 화면 진입/앱 재실행 시 단발 fetch로 표시하고, 사용자가 pull-to-refresh로 최신화한다. 현재 목록 source는 `users/{uid}/joinedRooms/{roomID}` projection이며, 해당 roomID로 `Rooms` 문서를 batch fetch한 뒤 클라이언트에서 `Rooms.lastMessageAt DESC`로 정렬한다.

대형 membership 전환 후 현재 계약:

- 참여중 목록은 `users/{uid}/joinedRooms/{roomID}` projection을 단발 fetch/pull-to-refresh로 읽는다.
- projection에는 `roomID`, `role`, `joinedAt`, `lastReadSeq`, `isClosed`, `updatedAt`만 둔다.
- 전체 참여자 배열과 `unreadCount`는 projection에 넣지 않는다.
- `lastMessage`, `lastMessageAt`, `lastMessageSeq`는 `Rooms/{roomID}` 문서만 source로 사용한다.
- 참여중 목록은 joinedRooms 전체 또는 충분한 범위 fetch 후 `Rooms` batch fetch, `Rooms.lastMessageAt DESC` 클라이언트 정렬로 구성한다.
- 메시지 전송 시 room metadata의 `lastMessage*`는 즉시 갱신하지만, 사용자별 projection의 `lastMessage*` fan-out은 하지 않는다.
- cutover 후 사용자 프로필 문서의 `joinedRooms` 배열은 bootstrap/runtime source로 사용하지 않는다.
- 관련 task: `docs/ai/tasks/chat-membership-model-transition/*`

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
- 앱이 아직 배포/운영 중이지 않고 데이터가 작으므로 legacy compatibility는 고려하지 않는다. 필요한 개발 데이터 정리는 사용자가 수동으로 처리한다.
- GRDB `RoomMember` table은 migration chain 호환 흔적으로 남아 있지만 production 참여자 목록 source나 write API로 사용하지 않는다.
- Profile sync manager: `OutPick/Features/Chat/Managers/Implementations/ChatProfileSyncManager.swift`
  - 메시지 발신자 UID 목록을 batch fetch하고 local user cache를 refresh한다.
  - 프로필 문서 listener/Combine publisher 경로는 사용하지 않는다.
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
