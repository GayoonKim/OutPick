# GRDB Module Design

## 목표

GRDBManager의 database bootstrap, migration, message, outbox, media index, profile cache, room cleanup 책임을 기능별 Store로 분리한다.

## 목표 흐름

~~~text
Chat UseCase / Manager / Repository
  → 기능별 Persistence Protocol
  → 기능별 GRDB Store
  → AppDatabase(DatabasePool)
  → GRDB
~~~

## 공통 AppDatabase 책임

- DatabasePool 생성과 수명.
- migration registry 실행.
- 공통 DB configuration.
- 테스트용 DatabasePool 주입.

AppDatabase는 채팅 메시지 query, media mapping, profile cache eviction 같은 기능 로직을 소유하지 않는다.

## Store 후보

- GRDBChatMessageStore
- GRDBOutgoingOutboxStore
- GRDBChatMediaIndexStore
- GRDBChatProfileCacheStore
- GRDBRoomLocalDataCleaner

## Record 후보

- ChatMessageRecord
- LocalChatUserRecord
- RoomProfileDisplayCacheRecord
- ImageIndexRecord
- VideoIndexRecord

N5는 D17로 확정했다. 기존 read model과 OutboxRecord는 유지하고, DB JSON/row mapping이 복잡한 메시지·프로필·미디어 타입만 persistence record와 mapper로 분리한다. 새 schema나 별도 domain 복제 모델은 만들지 않는다.

## 기존 경계 활용

GRDBManager는 ChatOutgoingOutboxPersisting을 이미 구현한다. 이 계약은 기능별 persistence Protocol 전환의 선행 사례로 사용하되, 하나의 Protocol이 다른 Store 책임까지 계속 확장되지 않게 한다.

## transaction 원칙

- 메시지 저장, FTS 반영, 해당 image/video index 갱신은 같은 write transaction을 유지한다.
- FTS 반영 실패를 삼키지 않고 상위로 전파해 메시지·FTS·미디어 전체를 rollback한다.
- 방 나가기의 메시지·FTS·미디어·outbox·방 프로필 캐시 삭제와 orphan profile pruning은 같은 transaction으로 처리한다.
- transient cleanup은 기존 의미대로 메시지·FTS·미디어만 삭제하고 outbox와 profile cache는 보존한다.
- Store가 나뉘어도 서로의 public API를 조합해 transaction을 흉내 내지 않는다.
- 여러 table을 함께 바꾸는 operation이 DatabasePool write closure와 transaction을 소유한다.

## migration 원칙

- 앱이 배포되지 않은 개발 단계이므로 D15의 clean break를 적용한다.
- `createUserProfile`, `addThumbAndOriginalToUserProfile`, `createRoomParticipant` no-op identifier와 `createRoomImage` migration/table/API를 제거해 fresh migration 기준선을 19개에서 15개로 줄인다.
- legacy 제거를 위한 `dropRoomImage` migration은 추가하지 않고 개발용 앱 DB를 삭제·재설치한다.
- 나머지 migration identifier/order와 table, column, index schema는 유지한다.
- rebuildChatMessageSenderUIDSchemaIfNeeded 동작과 기존 migration test를 보존한다.
- 새 migration registry는 schema definition과 runtime query의 소유권을 분리한다.
- 최초 운영 배포 이후에는 migration을 다시 append-only 호환 계약으로 취급한다.

## 확정 문서

- 결정: [Phase 3 GRDB 결정](../decisions/phase-3-grdb.md)
- 구현 계획: [Phase 3 GRDB](../phases/phase-3-grdb.md)
- 테스트 계획: [Phase 3 GRDB 테스트](../phases/phase-3-grdb-tests.md)

## 완료 기준

- AppDatabase가 DatabasePool과 migration을 소유한다.
- message/outbox/media/profile/cleanup 소비자가 필요한 Protocol만 받는다.
- GRDBManager giant public surface가 제거된다.
- transaction과 migration 회귀 테스트가 통과한다.
- room cleanup, profile LRU, failed outbox 같은 비동기/경계 동작을 독립 검증할 수 있다.
