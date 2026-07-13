# Data Entrypoints

## 목적

OutPick의 로컬 DB, Firestore schema, Repository data boundary를 수정할 때 어디부터 봐야 하는지 빠르게 확인하기 위한 문서다.

작업 시작 시에는 먼저 `docs/ai/DATA_SCHEMA.md`에서 현재 schema 결정을 확인하고, 필요한 코드 진입점만 추가로 읽는다.

## GRDB 로컬 캐시

- DB bootstrap: `OutPick/DB/GRDB/Core/AppDatabase.swift`
- 앱 bootstrap 오류/복구: `OutPick/App/Bootstrap/`, `OutPick/App/AppCompositionRoot.swift`, `OutPick/App/SceneDelegate.swift`
- migration registry/rebuilder: `OutPick/DB/GRDB/Migrations/`
- 기능별 query/transaction: `OutPick/DB/GRDB/Stores/`
- persistence record/mapper: `OutPick/DB/GRDB/Records/`, `OutPick/DB/GRDB/Mappers/`
- Chat persistence 계약/조립: `OutPick/Features/Chat/Persistence/`
- GRDB migration/cache tests: `OutPickTests/GRDB/`
- Chat profile display cache boundary: `docs/ai/entrypoints/CHAT.md`의 `프로필 표시와 참여자 캐시`
- Data schema 결정: `docs/ai/DATA_SCHEMA.md`의 `로컬 Chat 표시 캐시`
- Phase 3 승인 결정: `docs/ai/tasks/core-infrastructure-modularization/decisions/phase-3-grdb.md`
- Phase 3 구현/테스트 계획: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-3-grdb.md`, `phase-3-grdb-tests.md`

현재 소스는 `AppDatabase` + 기능별 Store 구조다. `AppDatabase.live()`는 DB 경로·migration 오류를 `throws`로 전달하며 SceneDelegate가 독립 실패 화면과 수동 재시도를 제공한다. fresh 기준선은 15개 migration이며 legacy no-op 3개와 `createRoomImage`/`roomImage` table/API는 없다. 메시지 저장 중 FTS 실패는 message/FTS/media transaction 전체를 rollback한다.

현재 GRDB chat profile cache 기준:

- `LocalChatUser`는 전역 profile display cache다.
- `RoomProfileDisplayCache(roomID, userID)`는 최근 메시지 sender 표시용 bounded relation이다.
- GRDB는 전체 room membership replica를 유지하지 않는다.
- `RoomMember` table/model/migration은 제거했다.
- legacy `userProfile`, `roomParticipant`, `LocalUser` GRDB compatibility는 유지하지 않는다.
- Phase 3 이전 19개 migration이 적용된 개발 DB는 앱 삭제/재설치로 초기화한다. 다만 migration fixture의 `chatMessage.senderID NOT NULL` 잔존 schema는 `ChatMessageSenderUIDSchemaRebuilder`와 `rebuildChatMessageSenderUIDSchema` migration으로 `senderUID` schema로 재작성한다.
- `chatMessage`의 현재 sender 식별 컬럼은 `senderUID`다. `senderID`는 legacy 잔존 컬럼이며 새 코드에서 insert하지 않는다.

GRDB cleanup/변경 시 우선 확인:

1. `docs/ai/DATA_SCHEMA.md`
2. `docs/ai/entrypoints/CHAT.md`
3. `OutPick/DB/GRDB/Core/AppDatabase.swift`, `OutPick/DB/GRDB/Migrations/`
4. 변경 작업에 해당하는 `OutPick/DB/GRDB/Stores/`와 `OutPick/Features/Chat/Persistence/` Protocol
5. `OutPickTests/GRDB/`와 위 Phase 3 결정·구현·테스트 문서

## Firestore Rules / Indexes

- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`
- Firebase entrypoint: `docs/ai/entrypoints/FIREBASE.md`
- Firestore workflow skill: `.codex/skills/firestore-workflow/SKILL.md`

Rules/indexes 변경 전 확인:

- membership source: `Rooms/{roomID}/members/{uid}`
- joined room projection: `users/{uid}/joinedRooms/{roomID}`
- legacy cleanup 대상: `Rooms.participantUIDs`, `users.{uid}.joinedRooms` 배열, `users/{uid}/roomStates/{roomID}`
- 비참여 preview read 정책은 `docs/ai/entrypoints/CHAT.md`의 `비참여 채팅방 Preview`를 확인한다.

## Firebase Storage Rules

- Storage rules 운영 상태와 read-only 조회 명령은 `docs/ai/entrypoints/FIREBASE.md`의 `Firebase Storage Rules`를 먼저 확인한다.
- Storage rules source: `storage.rules`
- Firebase deploy config: `firebase.json`의 `"storage": { "rules": "storage.rules" }`
- 2026-07-03 이전 운영 Storage rules는 전역 `allow read, write;` 상태였다.
- 2026-07-03 로컬 `storage.rules` 초안과 root `firebase.json` storage 설정을 추가했고, `firebase deploy --only storage --project outpick-664ae --dry-run --non-interactive` compile은 통과했다.
- 2026-07-03 `firebase deploy --only storage --project outpick-664ae --non-interactive`로 기본 deny + path별 최소 권한 rules 운영 배포를 완료했다.
- 운영 release는 `projects/outpick-664ae/releases/firebase.storage/outpick-664ae.appspot.com`, ruleset은 `projects/outpick-664ae/rulesets/148e8921-6195-42df-b575-09b17bbc88c4`다.
- Firebase Storage service agent의 cross-service Firestore lookup을 위해 `roles/firebaserules.firestoreServiceAgent` IAM binding을 추가했다.
- 확인 완료: room membership 생성 후 참여자 이미지/비디오 메시지 업로드, 방장 room cover 생성/수정/삭제.
- 2026-07-04 남은 수동 QA 완료: 비참여 preview 이미지/비디오 read, profile avatar 업로드, lookbook brand logo/season cover 업로드, legacy prefix 미사용 확인.
- Storage rules 추가/수정/배포는 사용자 명시 승인 없이 진행하지 않는다.

## Firebase Repository Boundary

공통 repository provider:

- `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseRepositoryProvider.swift`

Chat repository:

- Protocol: `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`
- Implementation: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`

User profile repository:

- Protocol/implementation: `OutPick/Features/Profile/Repository`와 `OutPick/DB/Firebase/DatabaseManager/Repositories`
- 주요 사용처: Login bootstrap, Chat profile fetch, Lookbook author profile fetch

Data 접근 원칙:

- View는 Firebase/GRDB/Functions를 직접 생성하지 않는다.
- ViewModel은 UseCase/Repository/Store를 생성자 주입으로 받는다.
- 서버 상태 변경은 Repository 또는 Cloud Functions 경계 뒤로 둔다.
- DTO/Firestore path 변경은 `docs/ai/DATA_SCHEMA.md`와 관련 entrypoint 문서를 함께 갱신한다.

## 검증

GRDB 변경:

```bash
xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'platform=iOS Simulator,id={available-simulator-id}' test -only-testing:OutPickTests/AppDatabaseMigrationTests -only-testing:OutPickTests/ChatMessageRecordMapperTests -only-testing:OutPickTests/GRDBChatMessageStoreTests -only-testing:OutPickTests/GRDBChatOutgoingOutboxStoreTests -only-testing:OutPickTests/GRDBChatMediaIndexStoreTests -only-testing:OutPickTests/GRDBChatProfileCacheStoreTests -only-testing:OutPickTests/GRDBChatRoomLocalDataStoreTests
xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'generic/platform=iOS Simulator' build
```

Firestore rules/indexes 변경:

- `.codex/skills/firestore-workflow/SKILL.md` 절차를 먼저 확인한다.
- 운영 deploy는 사용자 명시 승인 후 진행한다.

Firebase Functions 변경:

- `.codex/skills/firebase-functions-workflow/SKILL.md` 절차를 먼저 확인한다.
- Functions deploy는 사용자 명시 승인 후 진행한다.
