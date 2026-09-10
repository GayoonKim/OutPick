# Data Entrypoints

## 미디어 선택·실패 복구 데이터

- `ChatMediaSelection.swift`/`ChatMediaSelectionRepository.swift`: 기존 `chatOutgoingOutbox.localPayloadJSON`에 `selectionID`, room/sender, 원본 index/path/type, `pendingChunk(messageID, indices)`를 기록한다. 신규 SQLite table/migration은 없다. 원본은 Application Support/ChatMediaSelections에 저장하고 backup에서 제외한다.
- child payload 저장 → parent 원본 소비 → 업로드 시작 순서다. 중간 종료는 child outbox를 확인해 이미 보존한 원본을 중복 분할하지 않는다. 삭제 전 빈 source 원장을 저장해 파일 삭제 뒤 DB 삭제 실패로 버블이 부활하지 않게 한다.
- `ChatOutgoingOutboxUseCase`: reserve 송신 전에 attempt identity를 저장한다. local 실패와 server processingStatus를 분리하고 `media_cleanup_pending`은 사용자 버블 없는 cleanup 재시도 원장이다.
- `GRDBChatMessageStore`/`GRDBChatOutgoingOutboxStore`: seq>0 확정에 대한 실패 overwrite/outbox 부활 차단, `deleteUnconfirmedMessage` 원자적 조건부 삭제. 공개 메시지 삭제용 `hardDeleteMessage` 계약은 유지한다.
- 서버 reservation receipt/TTL은 `entrypoints/FIREBASE.md` 참조. 로컬 구현만 반영됐으며 원격 배포 상태는 해당 작업 progress를 확인한다.

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

Phase 7.5 deletion marker는 `chatDeletedMessageMarker.anonymizesSender`를 저장한다. 일반·관리자 삭제는 `false`로 sender UID·닉네임·아바타·전송 시각·답장 presentation을 로컬 메시지에 유지하고 본문·미디어·FTS만 제거한다. 계정 탈퇴 bulk는 `true`로 UID·아바타·답장 정보를 제거하고 닉네임을 `알 수 없는 사용자`로 바꾸되 전송 시각은 유지한다. `addDeletionMarkerSenderPolicy` migration은 기존 marker를 개인정보 재노출 방지 우선의 `true`로 backfill한다. 이후 서버가 직접 반환한 같은/더 최신 revision tombstone은 canonical sender 필드 유무로 이 policy를 exact 교정한다. `ChatMessageRecordMapper`도 삭제 메시지의 presentation을 그대로 저장하고 content만 제거하므로 재진입 server fetch가 닉네임·시간·답장을 다시 지우지 않는다.

## Firestore Rules / Indexes

- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`
- Firebase entrypoint: `docs/ai/entrypoints/FIREBASE.md`
- Firestore workflow skill: `.codex/skills/firestore-workflow/SKILL.md`
- 스타일 무드 schema/policy: `docs/ai/DATA_SCHEMA.md`의 `스타일 무드 계약`, `functions/src/styleMoods/`
- 스타일 무드 seed/index 검증: `functions/seeds/style-moods.v1.json`, `firestore-tests/style-moods.rules.test.mjs`

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
- 운영 release는 `projects/outpick-664ae/releases/firebase.storage/outpick-664ae.appspot.com`, 현재 ruleset은 `projects/outpick-664ae/rulesets/e0e75181-a23b-4dcf-a13c-df95bb9a70c6`다.
- Firebase Storage service agent의 cross-service Firestore lookup을 위해 `roles/firebaserules.firestoreServiceAgent` IAM binding을 추가했다.
- 확인 완료: room membership 생성 후 참여자 이미지/비디오 메시지 업로드, 방장 room cover 생성/수정/삭제.
- 2026-07-04 남은 수동 QA 완료: 비참여 preview 이미지/비디오 read, profile avatar 업로드, lookbook brand logo/season cover 업로드, legacy prefix 미사용 확인.
- 2026-07-30 active 계정 검사를 추가한 뒤 브랜드 asset write가 Storage rules의 Firestore 교차 조회 2문서 한도를 넘겨 거부된 회귀를 수정했다. 브랜드 존재 조회를 제거하고 active 사용자 + 총 관리자/브랜드 관리자 두 문서만 조회하며 emulator 회귀 테스트 후 운영 배포했다.
- Storage rules 추가/수정/배포는 사용자 명시 승인 없이 진행하지 않는다.

## Firebase Repository Boundary

공통 repository provider:

- `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseRepositoryProvider.swift`

Chat repository:

- Protocol: `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`
- Implementation: `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
- Room read DTO: `OutPick/DB/Firebase/DatabaseManager/DTOs/ChatRoomFirestoreDTO.swift`
- Room read/write mapper: `OutPick/DB/Firebase/DatabaseManager/Mappers/ChatRoomFirestoreMapper.swift`
- Room identity는 snapshot document ID를 mapper에 주입하며, 생성 payload는 자기 `ID`/`id`와 legacy `participantUIDs`를 제외한다.

User profile repository:

- 계정 read: `CurrentUserAccountRepositoryProtocol`, `FirestoreCurrentUserAccountRepository`
- 공개 프로필 read: `UserPublicProfileRepositoryProtocol`, `FirestoreUserPublicProfileRepository`
- mutation: `ProfileMutationRepositoryProtocol`, `CloudFunctionsProfileMutationRepository`
- 앱 bootstrap: `LoadCurrentUserBootstrapUseCase`
- Chat 참여자·메시지 프로필 cache, Lookbook 댓글 작성자와 사용자 상세은 `UserPublicProfileRepositoryProtocol`을 직접 사용한다.
- `UserProfileRepository`는 joinedRooms read state와 device/push 하위 상태처럼 공개 프로필이 아닌 기존 사용자 하위 데이터 책임만 유지한다.

Data 접근 원칙:

- View는 Firebase/GRDB/Functions를 직접 생성하지 않는다.
- ViewModel은 UseCase/Repository/Store를 생성자 주입으로 받는다.
- 서버 상태 변경은 Repository 또는 Cloud Functions 경계 뒤로 둔다.
- DTO/Firestore path 변경은 `docs/ai/DATA_SCHEMA.md`와 관련 entrypoint 문서를 함께 갱신한다.

Firestore 문서 ID 경계:

- canonical source: `DocumentSnapshot.documentID`.
- Repository가 경로 ID를 DTO→Domain mapper에 명시적으로 전달한다.
- 자기 문서의 기본키는 write payload의 `ID`/`id`로 중복 저장하지 않는다.
- 부모·컨텍스트 ID와 query projection용 ID는 별도 데이터 계약으로 유지한다.
- 상세 결정과 진행 상태: ADR-020, `docs/ai/tasks/firestore-document-id-boundary-cleanup/`.
- Chat 구현을 찾을 때는 `CHAT.md`의 `채팅방 Firestore ID 경계와 생성`, Lookbook 구현을 찾을 때는 `LOOKBOOK.md`의 `Firestore 문서 ID 경계` 표에서 DTO→Mapper→Repository 순서로 확인한다.
- rules·배포·운영 cleanup 상태는 `FIREBASE.md`, 자동·수동 검증은 `TESTS.md`와 task `qa-checklist.md`를 확인한다.

## 검증

GRDB 변경:

```bash
xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'platform=iOS Simulator,id={available-simulator-id}' test -only-testing:OutPickTests/AppDatabaseMigrationTests -only-testing:OutPickTests/ChatMessageRecordMapperTests -only-testing:OutPickTests/GRDBChatMessageStoreTests -only-testing:OutPickTests/GRDBChatOutgoingOutboxStoreTests -only-testing:OutPickTests/GRDBChatMediaIndexStoreTests -only-testing:OutPickTests/GRDBChatProfileCacheStoreTests -only-testing:OutPickTests/GRDBChatRoomLocalDataStoreTests
xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'generic/platform=iOS Simulator' build
```

Firestore rules/indexes 변경:

- `.codex/skills/firestore-workflow/SKILL.md` 절차를 먼저 확인한다.
- rules emulator 계약 테스트는 `firestore-tests/`에서 `npm test`로 실행한다.
- 운영 deploy는 사용자 명시 승인 후 진행한다.

Firebase Functions 변경:

- `.codex/skills/firebase-functions-workflow/SKILL.md` 절차를 먼저 확인한다.
- Functions deploy는 사용자 명시 승인 후 진행한다.
