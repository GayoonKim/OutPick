# OutPick Handoff

## 1. 최종 목표

- 2026-07-03 기준 chat identity/membership/profile cache boundary 핵심 전환은 완료했다.
- 현재 진행 중인 메인 task는 없다.
- 완료 처리한 핵심 작업:
  - `chat-legacy-identity-naming`
  - `chat-membership-model-transition` 핵심 구현 및 운영 배포
  - 운영 smoke QA 기반 legacy cleanup/index 배포 결정 및 실행
  - `chat-member-profile-cache-boundary` Phase 1~4
- 다음 추천 작업은 `grdb-schema-cleanup` 설계 하네스다.

## 2. 완료한 작업

### `chat-legacy-identity-naming`

- canonical user ID 기준 명명을 `userID`로 정리했다.
- `LocalChatUser.userID`, `RoomMember.userID` 등 Swift/API/GRDB 물리 schema를 Firebase Auth UID 의미로 맞췄다.
- legacy `userProfile`/`roomParticipant` runtime fallback과 backfill 동작을 제거했다.
- 프로필 문서 없는 사용자 fallback은 UID suffix가 아니라 “알 수 없는 사용자”로 표시한다.
- 최종 검증:
  - forbidden pattern 재검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

### `chat-membership-model-transition`

- membership authoritative source를 `Rooms/{roomID}/members/{uid}`로 전환했다.
- joined room projection은 `users/{uid}/joinedRooms/{roomID}`에 `roomID`, `role`, `joinedAt`, `lastReadSeq`, `isClosed`, `updatedAt` 중심으로 둔다.
- 참여중 목록은 joinedRooms projection fetch 후 `Rooms` batch fetch, 클라이언트 `Rooms.lastMessageAt DESC` 정렬로 구성한다.
- `lastMessage`, `lastMessageAt`, `lastMessageSeq`는 joined room projection에 fan-out하지 않는다.
- unread는 `Rooms.lastMessageSeq - users/{uid}/joinedRooms/{roomID}.lastReadSeq`로 계산한다.
- Socket room access, push fanout, 방장 close cleanup은 `Rooms/{roomID}/members` 기준으로 전환했다.
- Functions `onRoomClosed`의 legacy `participantUIDs` 배열 기반 cleanup은 Socket 즉시 cleanup과 충돌하지 않도록 비활성화했다.
- 운영 배포:
  - 2026-07-03 Socket Cloud Run `outpick-socket` revision `outpick-socket-00004-76z` 100% traffic 배포 완료
  - 2026-07-03 `firebase deploy --only firestore:rules --project outpick-664ae` 완료
  - 2026-07-03 `firebase deploy --only functions --project outpick-664ae` 완료
  - 2026-07-03 `firebase deploy --only firestore:indexes --project outpick-664ae --force` 완료
- 운영 legacy field count는 0으로 확인했다.

### `chat-member-profile-cache-boundary`

- 설계:
  - `LocalChatUser`는 전역 profile display cache다.
  - `RoomProfileDisplayCache(roomID, userID)`는 최근 메시지 sender 표시 전용 bounded relation이다.
  - room당 최대 20명, time-based TTL 없음, `lastSeenAt`/`lastMessageSeq` 기준 LRU eviction을 사용한다.
  - 설정 화면 참여자 목록은 remote `Rooms/{roomID}/members` pagination을 source로 한다.
  - local display cache는 전체 참여자 목록 대체 source로 쓰지 않는다.
- Phase 1:
  - `GRDBManager`에 `RoomProfileDisplayCache` model/table/migration/API를 추가했다.
  - room cleanup에서 `RoomProfileDisplayCache`를 삭제한다.
  - orphan `LocalChatUser` prune 기준을 display cache 중심으로 정리했다.
- Phase 2:
  - `ChatMessageManager`의 incoming/fetched message 저장 경로가 sender snapshot으로 `LocalChatUser`를 upsert하고 `RoomProfileDisplayCache`를 갱신한다.
  - 메시지 경로의 `RoomMember` write를 제거했다.
  - `ChatProfileSyncManager`는 `LocalChatUser` refresh만 담당한다.
- Phase 3:
  - `LoadChatRoomParticipantsUseCase`를 remote members pagination source로 전환했다.
  - 전체 members fetch + local `RoomMember` reconcile을 제거했다.
  - `ChatRoomParticipantsRepositoryProtocol`은 `LocalChatUser` read/upsert만 남겼다.
- Phase 4:
  - production 경계의 local membership replica API를 제거했다.
  - `RoomMember` table/model/migration은 migration chain 호환 흔적으로만 유지한다.
  - `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/CHAT.md`, task docs를 최신 구조로 갱신했다.
- 최종 검증:
  - forbidden pattern 검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

## 3. 아직 남은 작업

1. `grdb-schema-cleanup`
   - 개발 중 누적된 GRDB migration/table 이름 흔적을 정리한다.
   - 후보 파일:
     - `OutPick/DB/GRDB/GRDBManager.swift`
     - `OutPickTests/GRDBManagerMigrationTests.swift`
     - `docs/ai/DATA_SCHEMA.md`
   - App Store/TestFlight 배포 이력이 있는 migration은 삭제하지 않는다.
   - 배포 이력이 없는 개발 중 legacy migration/table 정리 가능 범위를 먼저 확정해야 한다.

2. `chat-membership-model-transition` destructive 수동 QA
   - 테스트 room 승인 후 운영 쓰기/삭제가 필요한 path를 확인한다.
   - 남은 QA:
     - 메시지 전송
     - 방 나가기
     - 방장 close
     - Storage `rooms/{roomID}/` prefix 삭제 확인

3. Socket dependency audit
   - Cloud Build 중 `npm audit` 취약점 경고가 있었다.
   - 배포는 성공했지만 실제 영향과 업데이트 가능성은 별도 점검이 필요하다.

4. Storage rules/preview 권한 확인
   - repo에서 Storage rules 파일은 확인되지 않았다.
   - 비참여 preview의 이미지/비디오 Storage 접근 권한은 실제 QA 전까지 확실하지 않음.

## 4. 수정한 파일 목록

- 최근 닫은 작업에서 중요한 파일:
  - `OutPick/DB/GRDB/GRDBManager.swift`
  - `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`
  - `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
  - `OutPick/Features/Chat/Domain/UseCases/LoadChatRoomParticipantsUseCase.swift`
  - `OutPick/Features/Chat/Repositories/ChatRoomParticipantsRepository.swift`
  - `OutPick/Features/Chat/Managers/Implementations/ChatMessageManager.swift`
  - `OutPick/Features/Chat/Managers/Implementations/ChatProfileSyncManager.swift`
  - `OutPickTests/GRDBManagerMigrationTests.swift`
  - `docs/ai/DATA_SCHEMA.md`
  - `docs/ai/entrypoints/CHAT.md`
  - `docs/ai/tasks/active.md`
  - `docs/ai/tasks/chat-member-profile-cache-boundary/*`
- working tree에는 이 작업 전부터 있던 앱/Socket/Functions/Firestore 변경이 많이 섞여 있다.
- 커밋 정리 전 `git status --short`와 `git diff --name-only`를 다시 확인해야 한다.

## 5. 중요한 아키텍처 결정

- membership source는 `Rooms/{roomID}/members/{uid}` 문서 존재 여부다.
- joined room projection은 최소 state만 담고 `lastMessage*`를 fan-out하지 않는다.
- 참여중 목록 정렬은 `Rooms` batch fetch 후 클라이언트 정렬로 처리한다.
- 방장 close cleanup은 job/state 문서 없이 즉시 성공/실패 응답으로 처리한다.
- 방장 destructive action의 최종 기준은 `Rooms.creatorUID`다.
- GRDB는 전체 room membership replica를 유지하지 않는다.
- `LocalChatUser`는 전역 profile display cache, `RoomProfileDisplayCache`는 최근 메시지 sender 표시용 bounded relation이다.
- 설정 화면 전체 참여자 목록은 remote members pagination만 source로 사용한다.
- `RoomMember` table/model/migration은 migration chain 호환 흔적으로만 남긴다.

## 6. 다시 확인해야 할 불확실한 부분

- Storage rules 파일은 repo에서 확인되지 않았다. 비참여 preview의 Storage 권한까지 통과하는지는 실제 QA 전까지 확실하지 않음.
- Socket dependency audit의 실제 영향도는 아직 확인하지 않았다.
- `grdb-schema-cleanup`에서 삭제 가능한 migration 범위는 배포 이력 기준으로 다시 확인해야 한다.

## 7. 다음 턴에서 바로 실행해야 할 작업

1. `grdb-schema-cleanup` 설계 하네스를 시작한다.
2. 관련 문서 우선 확인:
   - `docs/ai/DATA_SCHEMA.md`
   - `docs/ai/entrypoints/CHAT.md`
   - `docs/ai/tasks/chat-member-profile-cache-boundary/plan.md`
   - `docs/ai/tasks/chat-member-profile-cache-boundary/progress.md`
3. 관련 코드 우선 확인:
   - `OutPick/DB/GRDB/GRDBManager.swift`
   - `OutPickTests/GRDBManagerMigrationTests.swift`
4. 배포 이력 있는 migration 보존 기준을 먼저 확정한 뒤 구현 여부를 결정한다.
