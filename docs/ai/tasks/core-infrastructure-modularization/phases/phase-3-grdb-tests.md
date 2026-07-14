# Phase 3 GRDB Test Plan

## 목적

GRDB 구조를 분리하면서 migration, JSON mapping, pagination, projection과 여러 table transaction의 결과가 유지되는지 임시 `DatabasePool`로 결정적으로 검증한다. 실제 Documents DB, Firebase와 Socket 서버는 사용하지 않는다.

## 위험도

- 변경 유형: 로컬 persistence 대규모 리팩터링과 일부 승인된 실패 정책 수정.
- 실패 비용: 메시지 누락, 검색 누락, 미디어 index 불일치, outbox 복구 실패, 방 나가기 후 개인정보성 로컬 데이터 잔존.
- 자동 테스트 우선 대상: migration, rollback, pagination, LRU, orphan prune, JSON fallback.
- 수동 QA 우선 대상: 실제 화면 스크롤·검색·미디어 표시·방 나가기 흐름.

## 공통 test support

기준 디렉터리: `OutPickTests/GRDB/TestSupport/`

| 파일 | 책임 |
| --- | --- |
| `TemporaryAppDatabase.swift` | 고유 임시 sqlite URL/DatabasePool 생성과 정리 |
| `GRDBTestFixtures.swift` | message, attachment, outbox, profile/media fixture |
| `GRDBSchemaInspector.swift` | migration identifier, table/column/index 조회 helper |

각 test는 독립 DB를 사용한다. production singleton이나 Documents `OutPick.sqlite`를 사용하지 않는다.

## 예상 테스트 파일

기준 디렉터리: `OutPickTests/GRDB/`

### `AppDatabaseMigrationTests.swift`

- fresh DB가 확정된 15개 migration을 순서대로 적용한다.
- 최종 table은 `LocalChatUser`, `RoomProfileDisplayCache`, `chatMessage`, `chatMessageFTS`, `imageIndex`, `videoIndex`, `chatOutgoingOutbox`다.
- `roomImage` table이 없다.
- `createUserProfile`, `addThumbAndOriginalToUserProfile`, `createRoomParticipant`, `createRoomImage` identifier가 없다.
- 기존 `senderID NOT NULL` fixture를 `senderUID` schema로 rebuild하고 유효 row를 backfill한다.
- rebuild 후 message index가 다시 생성된다.
- legacy invalid row filtering 결과를 현재 migration test와 동일하게 고정한다.

기존 `OutPickTests/GRDBManagerMigrationTests.swift` 시나리오는 이 파일로 이전하고 기존 파일은 제거한다.

### `ChatMessageRecordMapperTests.swift`

- attachments를 index 순으로 정렬해 JSON string으로 encode한다.
- reply preview와 lookbook shared content round trip.
- legacy message type decode.
- nil/빈 optional column decode.
- attachments encode 실패 시 `[]`, optional JSON encode 실패 시 nil fallback을 유지한다.
- malformed stored JSON의 기존 decode/fallback 결과를 고정한다.
- `LocalChatUserRecord`와 Domain `LocalChatUser` round trip.
- media Record가 기존 `ImageIndexMeta`/`VideoIndexMeta`로 동일 mapping된다.

### `GRDBChatMessageStoreTests.swift`

- 여러 message save와 recent/before/after/older/newer pagination 정렬·limit.
- 단일 fetch, count, failed outgoing fetch.
- message save 시 FTS와 image/video projection이 같이 생성된다.
- 동일 message 재저장 시 media projection이 중복 없이 교체된다.
- 삭제 message 저장 시 media projection을 제거한다.
- FTS table을 의도적으로 제거해 insert를 실패시키면 message와 media row가 모두 rollback된다.
- `applyDeletion`이 target `isDeleted`, referencing reply preview, image/video 삭제를 한 transaction에서 처리한다.
- delete failure trigger로 중간 실패를 만들면 message/reply/media 상태가 모두 rollback된다.
- hard delete가 message/FTS/media를 함께 삭제한다.
- prune이 보존 대상과 관련 projection만 남긴다.
- local FTS 검색 결과와 keyword filtering을 검증한다.
- 필수 식별자가 비어 있는 message만 skip되고 같은 batch의 유효 message는 저장된다.
- 3,300/3,000 prune threshold 호출 결과를 고정한다.

### `GRDBChatOutgoingOutboxStoreTests.swift`

- outbox save/fetch/update/delete.
- stage와 optional payload/error round trip.
- 기존 absolute local path를 현재 outbox root 상대 경로로 복원하는 동작.
- 존재하지 않는 record 조회는 nil.
- Outbox Store가 message table을 직접 변경하지 않는지 검증한다.

### `GRDBChatMediaIndexStoreTests.swift`

- image/video count와 latest 정렬.
- sentAt/messageID cursor 기반 older pagination.
- remote metadata entry upsert idempotency.
- image/video 개별 row와 message 단위 delete.
- video duration metadata가 기존 값이 없을 때만 채워지는 `COALESCE` 의미.
- 내부 Record에서 read model mapping.

### `GRDBChatProfileCacheStoreTests.swift`

- local user upsert/fetch.
- room display cache upsert와 user ID 정렬.
- 같은 write에서 최대 20명 LRU eviction.
- lastSeenAt/lastMessageSeq/userID tie-break 순서.
- current user 관련 row가 필요한 시나리오에서 유지된다.
- profile Record와 Domain mapping.

### `GRDBChatRoomLocalDataStoreTests.swift`

- transient cleanup은 message/FTS/image/video만 제거한다.
- transient cleanup은 outbox와 RoomProfileDisplayCache를 유지한다.
- exit cleanup은 message/FTS/media/outbox/display cache를 모두 제거한다.
- exit cleanup 뒤 다른 room에서 참조하는 LocalChatUser는 유지한다.
- orphan local user는 제거한다.
- current user는 어떤 room cache에도 없어도 유지한다.
- delete failure trigger로 중간 실패 시 room data와 user prune이 모두 rollback된다.
- legacy `roomImage` table이 없어도 별도 분기 없이 동작한다.

## 기존 테스트 수정

- `OutPickTests/ChatOutgoingOutboxUseCaseTests.swift`
  - outbox persistence fake와 failed-message persistence fake를 분리한다.
  - 기존 stage/retry/delete/file cleanup 시나리오는 유지한다.
- `OutPickTests/ChatProfileSyncManagerTests.swift`
  - concrete `GRDBManager` 대신 `ChatProfileCachePersisting` fake 또는 임시 Profile Store를 주입한다.
- `OutPickTests/ChatRoomExitUseCaseTests.swift`
  - local persistence spy와 session cleanup 순서/실패 허용 정책을 유지한다.
- search/message manager 관련 기존 test가 concrete manager를 사용하면 새 persistence fake로 교체한다.

## failure injection 방법

- FTS rollback: migration 후 test DB의 `chatMessageFTS`를 drop하고 save를 실행한다.
- delete/cleanup rollback: test-only SQLite trigger에서 `RAISE(ABORT, ...)`를 발생시킨다.
- mapper failure: non-finite number 등 `JSONEncoder`가 실패하는 fixture를 사용하되 실제 Domain type으로 재현 불가능하면 mapper encoder 주입을 test-only seam으로 둔다.
- 날짜/LRU: 고정 Date fixture를 사용하고 wall clock에 의존하지 않는다.

test seam은 production 동작을 바꾸지 않는 최소 범위로 둔다. 인위적 generic repository mock layer는 추가하지 않는다.

## 추가하지 않는 테스트

- UI snapshot: 화면 변경이 아니다.
- Firebase/Socket integration: 외부 계약을 바꾸지 않으며 로컬 transaction 검증과 무관하다.
- 실제 Documents DB migration: 아직 운영 배포 전 clean break이므로 개발 DB는 초기화한다.
- `roomImage` GRDB migration 호환 test: D15에서 호환 자체를 제거했다.
- 성능 benchmark: 구조 이동 후 실제 병목이 확인되지 않았으므로 범위 밖이다.

## 정적 검증

```bash
rg -n "GRDBManager|GRDBManager\.shared" OutPick OutPickTests
rg -n "DatabasePool\(|DatabaseQueue\(" OutPick -g '*.swift'
rg -n "roomImage|createUserProfile|addThumbAndOriginalToUserProfile|createRoomParticipant" OutPick/DB/GRDB OutPickTests/GRDB -g '*.swift'
```

기대 결과:

- 첫 검색은 결과가 없어야 한다.
- 두 번째 검색은 `AppDatabase`와 명시적 test support만 반환해야 한다.
- 세 번째 검색은 결과가 없어야 한다. Firebase Storage의 room image 코드는 검색 범위 밖이며 유지한다.

## targeted test 명령

사용 가능한 Simulator ID를 확인한 뒤 실행한다.

```bash
xcodebuild -project OutPick.xcodeproj -scheme OutPick \
  -destination 'platform=iOS Simulator,id={available-simulator-id}' test \
  -only-testing:OutPickTests/AppDatabaseMigrationTests \
  -only-testing:OutPickTests/ChatMessageRecordMapperTests \
  -only-testing:OutPickTests/GRDBChatMessageStoreTests \
  -only-testing:OutPickTests/GRDBChatOutgoingOutboxStoreTests \
  -only-testing:OutPickTests/GRDBChatMediaIndexStoreTests \
  -only-testing:OutPickTests/GRDBChatProfileCacheStoreTests \
  -only-testing:OutPickTests/GRDBChatRoomLocalDataStoreTests \
  -only-testing:OutPickTests/ChatOutgoingOutboxUseCaseTests \
  -only-testing:OutPickTests/ChatProfileSyncManagerTests \
  -only-testing:OutPickTests/ChatRoomExitUseCaseTests
```

## build 명령

```bash
xcodebuild -project OutPick.xcodeproj -scheme OutPick \
  -destination 'generic/platform=iOS Simulator' build
```

## 수동 QA

- 개발 Simulator 앱 삭제·재설치 후 앱 시작과 DB 생성.
- 채팅방 진입 시 최근 message와 unread anchor 표시.
- 이전/이후 pagination과 빠른 재진입.
- offline/local fallback 검색과 online 검색.
- 이미지/동영상 모아보기 pagination과 duration 표시.
- 이미지/동영상 failed outgoing message 재시도와 local delete.
- transient reconnect 후 local cache 재구성.
- 방 나가기/방 닫기 후 목록·세션 상태와 재진입 차단.
- 다른 방의 참여자 표시 캐시가 cleanup 후 유지되는지 확인.

## 실행 정책

- Phase 3 구현 완료 후 targeted tests와 generic build를 실제 실행한다.
- migration, local deletion과 outbox는 실패 비용이 높으므로 테스트 작성 후 실행을 보류하지 않는다.
- 수동 QA 미수행 항목은 이유와 함께 progress에 기록한다.

## 실행 결과

- 2026-07-13 Simulator `5A3BB941-9538-4DD9-93C2-F18ACCFB03B9`에서 위 targeted test 10개 suite가 통과했다.
- `generic/platform=iOS Simulator`, `CODE_SIGNING_ALLOWED=NO` build가 통과했다.
- `GRDBManager`/pass-through repository 잔여, production `DatabasePool` 소유권, legacy migration/API 검색과 `git diff --check`가 통과했다.
- 수동 QA는 실제 앱 조작이 필요한 항목이므로 이번 구현 턴에서는 수행하지 않았다.

## D19 bootstrap 후속 테스트 계획

구현 파일:

- `OutPickTests/AppBootstrapFailureInjectorTests.swift`
  - argument 없음은 실패하지 않는다.
  - `--app-bootstrap-fail-database-once`는 첫 호출만 실패하고 두 번째 호출은 통과한다.
  - `--app-bootstrap-fail-database-always`는 모든 호출이 실패한다.
- `OutPickTests/AppCompositionRootTests.swift`
  - 주입한 database factory 오류를 `AppBootstrapError.localDatabaseInitializationFailed`로 mapping한다.
  - 실패 factory 실행 뒤 Coordinator가 생성되지 않는다.
  - `AppDatabase.live()` 호출부에 `try!`/`try?`/대체 `fatalError`가 없다.
- `OutPickUITests/AppBootstrapFailureUITests.swift`
  - `once` argument로 초기 실패 화면 제목과 `다시 시도` 버튼을 확인한다.
  - 재시도 후 실패 화면이 사라지고 정상 app root로 진입한다.
  - `always` argument에서 반복 재시도해도 crash나 중복 Coordinator 없이 실패 화면을 유지한다.

수동 QA:

- Simulator를 `once` argument로 실행해 실패 화면과 재시도 성공을 확인한다.
- `always` argument로 반복 실패와 foreground/background lifecycle 안전성을 확인한다.
- 알림 launch route를 bootstrap 전에 저장해 `once` 실패 후 재시도에서도 route가 보존되는지 확인한다.
- 실제 SQLite 파일 손상·삭제는 수행하지 않는다.

D19는 앱 시작 경계와 실패 복구를 바꾸므로 targeted unit/UI tests와 generic Simulator build를 실제 실행한다.

### D19 실행 결과

- 2026-07-14 Simulator `7544249E-D0EE-4B88-A48F-E384DF84E6A4`에서 `AppBootstrapFailureInjectorTests` 4개와 `AppCompositionRootTests` 1개가 통과했다.
- 같은 Simulator에서 `AppBootstrapFailureUITests`의 once 복구와 always 반복 실패 2개가 통과했다.
- `generic/platform=iOS Simulator`, `CODE_SIGNING_ALLOWED=NO` build가 통과했다.
- DB bootstrap `fatalError`/`try!`/SQLite 삭제 잔여 검색과 `git diff --check`가 통과했다.
