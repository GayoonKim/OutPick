# Active Task

## 현재 상태

- 현재 진행 중인 메인 task는 없다.
- 2026-07-03 기준 아래 핵심 작업은 완료/마감 처리했다.
  - `chat-legacy-identity-naming`
  - `chat-membership-model-transition` 핵심 구현 및 운영 배포
  - 운영 smoke QA 기반 legacy cleanup/index 배포 결정 및 실행
  - `chat-member-profile-cache-boundary` Phase 1~4

## 완료한 핵심 작업

### 1. `chat-legacy-identity-naming`

- canonical user ID 기준 명명을 `userID`로 정리했다.
- `LocalChatUser.userID`, `RoomMember.userID` 등 Swift/API/GRDB 물리 schema를 canonical UID 의미로 맞췄다.
- legacy `userProfile`/`roomParticipant` runtime fallback은 제거했다.
- 최종 검증:
  - forbidden pattern 재검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

### 2. `chat-membership-model-transition`

- membership authoritative source를 `Rooms/{roomID}/members/{uid}`로 전환했다.
- 참여중 목록 source를 `users/{uid}/joinedRooms/{roomID}` projection + `Rooms` batch fetch + 클라이언트 정렬로 전환했다.
- Socket room access, push fanout, 방장 close cleanup, Firestore rules, Functions cleanup 경계를 새 membership 모델에 맞췄다.
- 운영 배포:
  - Socket Cloud Run `outpick-socket` revision `outpick-socket-00004-76z` 100% traffic 배포 완료
  - `firebase deploy --only firestore:rules --project outpick-664ae` 완료
  - `firebase deploy --only functions --project outpick-664ae` 완료
  - `firebase deploy --only firestore:indexes --project outpick-664ae --force` 완료
- 운영 legacy field count는 0으로 확인했다.

### 3. `chat-member-profile-cache-boundary`

- Phase 1:
  - `RoomProfileDisplayCache(roomID, userID)` GRDB schema/API/migration 추가
  - room당 20명 LRU eviction 구현
  - room cleanup과 orphan `LocalChatUser` prune 기준 반영
- Phase 2:
  - 메시지 저장 경로가 `LocalChatUser` + `RoomProfileDisplayCache`만 갱신하도록 전환
  - 메시지 경로의 local `RoomMember` write 제거
- Phase 3:
  - 설정 참여자 목록 source를 remote `Rooms/{roomID}/members` pagination으로 전환
  - 전체 members fetch + local `RoomMember` reconcile 제거
- Phase 4:
  - production 경계의 local membership replica API 제거
  - `RoomMember` table/model/migration은 migration chain 호환 흔적으로만 유지
  - `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/CHAT.md` 갱신
- 최종 검증:
  - forbidden pattern 검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

## 남은 작업 목록

### 1. `grdb-schema-cleanup`

- 목적:
  - 개발 중 누적된 GRDB migration/table 이름 흔적을 정리한다.
- 범위 후보:
  - `OutPick/DB/GRDB/GRDBManager.swift`
  - `OutPickTests/GRDBManagerMigrationTests.swift`
  - `docs/ai/DATA_SCHEMA.md`
- 결정 필요:
  - App Store/TestFlight 배포 이력이 있는 migration은 보존한다.
  - 배포 이력이 없는 개발 중 legacy migration/table 정리 가능 범위를 확정해야 한다.
- 권장 검증:
  - `GRDBManagerMigrationTests`
  - iOS generic simulator build

### 2. `chat-membership-model-transition` destructive 수동 QA

- 목적:
  - 운영 쓰기/삭제가 필요한 destructive path를 테스트 room 기준으로 확인한다.
- 남은 QA:
  - 메시지 전송
  - 방 나가기
  - 방장 close
  - Storage `rooms/{roomID}/` prefix 삭제 확인
- 조건:
  - 테스트 room 승인 후 진행한다.

### 3. Socket Dependency Audit

- 목적:
  - Cloud Build 중 확인된 `npm audit` 취약점 경고를 별도 점검한다.
- 현재 상태:
  - 배포는 성공했다.
  - 취약점 실제 영향과 업데이트 가능성은 아직 검토하지 않았다.

### 4. Storage Rules/Preview 권한 확인

- 목적:
  - 비참여 preview에서 이미지/비디오 Storage 접근이 실제 정책으로 막히지 않는지 확인한다.
- 현재 상태:
  - repo에서 Storage rules 파일은 확인되지 않았다.
  - 실제 QA 전까지 Storage 권한 경계는 확실하지 않음.

## 다음 추천 순서

1. `grdb-schema-cleanup` 설계 하네스 진행
2. destructive 수동 QA용 테스트 room 확정 후 membership close/leave QA
3. Socket dependency audit
4. Storage preview 권한 확인
