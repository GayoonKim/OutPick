# Data Entrypoints

## 목적

OutPick의 로컬 DB, Firestore schema, Repository data boundary를 수정할 때 어디부터 봐야 하는지 빠르게 확인하기 위한 문서다.

작업 시작 시에는 먼저 `docs/ai/DATA_SCHEMA.md`에서 현재 schema 결정을 확인하고, 필요한 코드 진입점만 추가로 읽는다.

## GRDB 로컬 캐시

- GRDB manager/migrations: `OutPick/DB/GRDB/GRDBManager.swift`
- GRDB migration/cache tests: `OutPickTests/GRDBManagerMigrationTests.swift`
- Chat profile display cache boundary: `docs/ai/entrypoints/CHAT.md`의 `프로필 표시와 참여자 캐시`
- Data schema 결정: `docs/ai/DATA_SCHEMA.md`의 `로컬 Chat 표시 캐시`

현재 GRDB chat profile cache 기준:

- `LocalChatUser`는 전역 profile display cache다.
- `RoomProfileDisplayCache(roomID, userID)`는 최근 메시지 sender 표시용 bounded relation이다.
- GRDB는 전체 room membership replica를 유지하지 않는다.
- `RoomMember` table/model/migration은 제거했다.
- legacy `userProfile`, `roomParticipant`, `LocalUser` GRDB compatibility는 유지하지 않는다.
- 기존 개발 DB가 깨지면 앱 삭제/재설치로 초기화할 수 있다. 다만 `chatMessage.senderID NOT NULL` 잔존 schema는 실제 메시지 저장 실패를 유발해 `GRDBManager.rebuildChatMessageSenderUIDSchemaIfNeeded(in:)`와 `rebuildChatMessageSenderUIDSchema` migration으로 `senderUID` schema로 재작성한다.
- `chatMessage`의 현재 sender 식별 컬럼은 `senderUID`다. `senderID`는 legacy 잔존 컬럼이며 새 코드에서 insert하지 않는다.

GRDB cleanup/변경 시 우선 확인:

1. `docs/ai/DATA_SCHEMA.md`
2. `docs/ai/entrypoints/CHAT.md`
3. `OutPick/DB/GRDB/GRDBManager.swift`
4. `OutPickTests/GRDBManagerMigrationTests.swift`

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
xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' test -only-testing:OutPickTests/GRDBManagerMigrationTests
xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'generic/platform=iOS Simulator' build
```

Firestore rules/indexes 변경:

- `.codex/skills/firestore-workflow/SKILL.md` 절차를 먼저 확인한다.
- 운영 deploy는 사용자 명시 승인 후 진행한다.

Firebase Functions 변경:

- `.codex/skills/firebase-functions-workflow/SKILL.md` 절차를 먼저 확인한다.
- Functions deploy는 사용자 명시 승인 후 진행한다.
