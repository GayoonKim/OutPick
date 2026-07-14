# Phase 3 GRDB Implementation Plan

## 상태

- 설계 결정: D15~D18 확정.
- 코드 구현: Step 3A~3G 완료.
- 테스트/빌드: targeted tests와 generic Simulator build 통과.
- 수동 QA: 미수행.
- 후속 안정화: D19 `AppDatabase.live()` throws, 실패 화면, 재시도와 DEBUG failure injection 구현·자동 검증 완료.
- 서버·배포 변경: 범위 밖.

## 목표

`GRDBManager`에 모인 DatabasePool bootstrap, migration, message/FTS/media projection, outbox, profile cache와 room cleanup을 공통 `AppDatabase`와 기능별 Store로 분리한다. 소비자는 필요한 persistence Protocol만 받고, 작업 단위 Store가 기존 또는 승인된 transaction 경계를 소유한다.

## 목표 흐름

```text
AppCompositionRoot
  → AppDatabase 1개 생성
  → AppCoordinator
  → ChatContainer
  → ChatPersistenceProvider
      ├── GRDBChatMessageStore
      ├── GRDBChatOutgoingOutboxStore
      ├── GRDBChatMediaIndexStore
      ├── GRDBChatProfileCacheStore
      └── GRDBChatRoomLocalDataStore

Chat Manager / UseCase / Repository
  → 소비자별 Persistence Protocol
  → 기능별 Store
  → AppDatabase(DatabasePool)
  → GRDB
```

## 변경하지 않는 범위

- Firestore, Firebase Storage, Socket event와 서버 API.
- 현재 GRDB table/column/index 중 D15가 승인한 legacy 제거 외 schema 의미.
- message pagination 정렬과 limit.
- 잘못된 필수 message만 skip하는 batch 정책.
- JSON encode fallback: attachments `[]`, optional reply/shared content `nil`.
- 3,300개 초과 감지와 3,000개 보존 prune 정책.
- transient cleanup에서 outbox/profile cache를 유지하는 의미.

## 의도적으로 변경하는 범위

- migration 등록은 legacy 4개를 제외한 15개 clean baseline으로 바뀐다.
- FTS insert 실패는 더 이상 삼키지 않고 message/FTS/media write 전체를 rollback한다.
- exit cleanup은 같은 room의 outbox도 같은 transaction에서 제거한다.
- 개발 Simulator/기기의 기존 앱 DB는 앱 삭제·재설치 또는 앱 데이터 초기화가 필요하다.

## 예상 변경 파일

### 1. 공통 database core — 새 파일

기준 디렉터리: `OutPick/DB/GRDB/Core/`

| 파일 | 책임 |
| --- | --- |
| `AppDatabase.swift` | Documents `OutPick.sqlite` DatabasePool 생성·보관, configuration, migration 실행, test pool 주입 |

`AppDatabase`는 기능 query, LRU, message mapping, cleanup SQL을 소유하지 않는다. production은 `AppCompositionRoot`가 한 번 생성하고 Store들이 같은 인스턴스를 공유한다.

### 2. migration registry — 새 파일

기준 디렉터리: `OutPick/DB/GRDB/Migrations/`

| 파일 | 책임 |
| --- | --- |
| `GRDBMigrationRegistry.swift` | 15개 migration identifier/order/schema 등록 |
| `ChatMessageSenderUIDSchemaRebuilder.swift` | legacy `senderID` schema 탐지·데이터 backfill·table/index 재생성 |

확정 migration 순서:

1. `foreignKeysOn`
2. `createLocalChatUser`
3. `createRoomProfileDisplayCache`
4. `createChatMessage`
5. `addSeqToChatMessage`
6. `migrateChatMessageSenderUID`
7. `createChatMessageFTS`
8. `addReplyPreviewToChatMessage`
9. `addIsDeletedToChatMessage`
10. `addSenderAvatarPathToChatMessage`
11. `addLookbookShareToChatMessage`
12. `rebuildChatMessageSenderUIDSchema`
13. `createImageIndex`
14. `createVideoIndex`
15. `createChatOutgoingOutbox`

제거 identifier:

- `createUserProfile`
- `addThumbAndOriginalToUserProfile`
- `createRoomParticipant`
- `createRoomImage`

### 3. persistence Record와 mapper — 새 파일

기준 디렉터리: `OutPick/DB/GRDB/Records/`

| 파일 | 책임 |
| --- | --- |
| `ChatMessageRecord.swift` | chatMessage scalar/JSON string column 표현 |
| `LocalChatUserRecord.swift` | LocalChatUser row와 GRDB conformance |
| `RoomProfileDisplayCacheRecord.swift` | room profile display cache row |
| `ChatMediaIndexRecords.swift` | imageIndex/videoIndex row 표현 |

기준 디렉터리: `OutPick/DB/GRDB/Mappers/`

| 파일 | 책임 |
| --- | --- |
| `ChatMessageRecordMapper.swift` | `ChatMessage` ↔ `ChatMessageRecord`, JSON/legacy message type/fallback |
| `ChatProfileRecordMapper.swift` | `LocalChatUserRecord` ↔ `LocalChatUser` |
| `ChatMediaIndexRecordMapper.swift` | 내부 media Record → 기존 `ImageIndexMeta`/`VideoIndexMeta` read model |

`ChatOutgoingOutboxRecord`는 이미 persistence 계약이므로 중복 Record를 추가하지 않는다.

### 4. 소비자별 persistence Protocol — 새 파일 또는 기존 파일 수정

기준 디렉터리: `OutPick/Features/Chat/Persistence/Protocols/`

| Protocol | 소비자 | 핵심 capability |
| --- | --- | --- |
| `ChatMessagePersisting` | `ChatMessageManager` | save, initial/around pagination, failed fetch, delete mutation, prune |
| `ChatMessageSearching` | `ChatSearchManager` | room FTS search |
| `ChatFailedOutgoingMessagePersisting` | `ChatOutgoingOutboxUseCase` | failed message save/fetch/hard delete 최소 subset |
| `ChatOutgoingOutboxPersisting` | `ChatOutgoingOutboxUseCase` | outbox record save/fetch/delete만 |
| `ChatMediaIndexPersisting` | media load/use case | count/latest/older/upsert/row delete/duration update |
| `ChatProfileCachePersisting` | message/profile sync/participants | local user와 display cache read/upsert |
| `ChatRoomLocalDataPersisting` | transient/exit cleaner | transient cleanup, exit cleanup+orphan prune |

기존 `OutPick/Features/Chat/Domain/UseCases/ChatOutgoingOutboxPersisting.swift`는 새 Protocol 위치로 이동하고 message method를 제거한다.

기존 소비자 Protocol 처리:

- `ChatRoomParticipantsRepositoryProtocol`은 유지하고 `GRDBChatProfileCacheStore`가 직접 conform한다.
- `ChatRoomMediaIndexRepositoryProtocol`은 유지하고 `GRDBChatMediaIndexStore`가 직접 conform한다.
- 별도 pass-through 구현인 `GRDBChatRoomParticipantsRepository`, `GRDBChatRoomMediaIndexRepository`는 제거한다.

### 5. 기능별 GRDB Store — 새 파일

기준 디렉터리: `OutPick/DB/GRDB/Stores/`

| 파일 | conform/책임 |
| --- | --- |
| `GRDBChatMessageStore.swift` | message persistence/search/failed-message subset, message+FTS+media transaction |
| `GRDBChatOutgoingOutboxStore.swift` | outbox record CRUD |
| `GRDBChatMediaIndexStore.swift` | independent media query/upsert/delete/duration |
| `GRDBChatProfileCacheStore.swift` | local user, display cache, LRU 20명 |
| `GRDBChatRoomLocalDataStore.swift` | transient cleanup, exit cleanup, orphan user prune |

Store는 `AppDatabase`를 생성하지 않고 생성자 주입받는다.

### 6. transaction helper — 새 파일

기준 디렉터리: `OutPick/DB/GRDB/Support/`

| 파일 | 책임 |
| --- | --- |
| `ChatMediaIndexSQL.swift` | message Store와 media Store가 같은 transaction의 `Database`를 받아 재사용하는 internal SQL helper |
| `ChatRoomCleanupSQL.swift` | room 단위 table 삭제와 orphan user prune internal helper |

helper는 `DatabasePool.write`를 열지 않는다. transaction은 항상 호출 Store가 소유한다.

### 7. DI provider — 새 파일

| 파일 | 책임 |
| --- | --- |
| `OutPick/Features/Chat/Persistence/ChatPersistenceProvider.swift` | 같은 AppDatabase로 5개 Store를 조립하고 Protocol 타입으로 노출 |

### 8. 기존 소비자·DI 수정 파일

앱 조립:

- `OutPick/App/AppCompositionRoot.swift`
- `OutPick/App/AppCoordinator.swift`
- `OutPick/Features/Chat/ChatContainer.swift`
- `OutPick/Features/Chat/ChatCompositionRoot.swift`
- `OutPick/Features/Chat/ChatCoordinator.swift`
- `OutPick/Features/Chat/Managers/ChatManagerProvider.swift`

소비자:

- `OutPick/Features/Chat/Managers/Implementations/ChatMessageManager.swift`
- `OutPick/Features/Chat/Managers/Implementations/ChatSearchManager.swift`
- `OutPick/Features/Chat/Managers/Implementations/ChatProfileSyncManager.swift`
- `OutPick/Features/Chat/Domain/UseCases/ChatOutgoingOutboxUseCase.swift`
- `OutPick/Features/Chat/Domain/UseCases/ChatRoomTransientLocalDataCleaner.swift`
- `OutPick/Features/Chat/Domain/UseCases/ChatRoomExitUseCase.swift`
- `OutPick/Features/Chat/Repositories/ChatRoomParticipantsRepository.swift`
- `OutPick/Features/Chat/Repositories/ChatRoomMediaIndexRepository.swift`

Domain type 이동/수정:

- `LocalChatUser`를 GRDB 파일에서 Chat Domain model 파일로 이동한다.
- `ImageIndexMeta`, `VideoIndexMeta`는 기존 이름과 소비자 계약을 유지하되 Chat persistence read model 위치로 이동한다.

### 9. 제거 파일

- `OutPick/DB/GRDB/GRDBManager.swift`

Phase 종료 시 `GRDBManager.shared`, concrete `GRDBManager` 주입과 직접 `DatabasePool` 소비자가 없어야 한다.

## Store/Protocol 상세 경계

### GRDBChatMessageStore

- message save/read/count/pagination/search.
- failed outgoing message 조회.
- 삭제 표시 operation은 message `isDeleted`, reply preview JSON, image/video projection 삭제를 한 write로 처리한다.
- hard delete와 prune은 대상 선정, message/FTS/media 삭제를 한 write로 처리한다.
- message save는 Record mapping 후 message row, FTS, image/video projection을 한 write로 처리한다.
- FTS 오류를 catch하지 않고 전파해 전체 rollback한다.
- threshold 확인과 prune 호출 시점은 기존처럼 save write 이후 유지한다.

### GRDBChatOutgoingOutboxStore

- outbox row CRUD와 기존 local file path migration decode를 소유한다.
- message table을 직접 변경하지 않는다.
- `ChatOutgoingOutboxUseCase`는 outbox Store와 failed-message capability를 각각 주입받는다.

### GRDBChatMediaIndexStore

- 화면 미디어 목록을 위한 count/latest/older query.
- remote metadata 기반 independent upsert.
- 개별 row delete와 video duration metadata update.
- message 저장·삭제 transaction에 필요한 projection SQL은 Message Store가 helper를 통해 직접 실행한다.

### GRDBChatProfileCacheStore

- local user fetch/upsert.
- room display cache upsert와 최대 20명 LRU eviction을 같은 write에서 처리한다.
- `LocalChatUserRecord`를 Domain `LocalChatUser`로 변환한다.

### GRDBChatRoomLocalDataStore

- transient cleanup: message/FTS/imageIndex/videoIndex만 한 write에서 삭제.
- exit cleanup: message/FTS/media/outbox/display cache 삭제 후 current user를 제외한 orphan local user prune.
- joined rooms in-memory state와 Firebase repository는 알지 않는다. `DefaultChatRoomLocalExitCleaner`가 로컬 Store 호출과 세션 상태 제거를 orchestration한다.

## 구현 순서

### Step 3A. migration characterization과 clean baseline

목표: 구조 이동 전에 기존 schema와 승인된 제거 범위를 test로 고정한다.

1. 기존 migration test를 15개 baseline으로 갱신한다.
2. fresh DB schema와 senderUID rebuild fixture를 분리한다.
3. `roomImage`와 legacy identifier 4개가 없는지 검증한다.
4. 개발 DB reset 조건을 문서화한다.

완료 기준: migration registry 구현 전에 기대 schema/order가 test로 명확하다.

### Step 3B. AppDatabase와 migration registry

1. `AppDatabase`, registry, senderUID rebuilder를 추가한다.
2. 기존 migration body를 동작 변경 없이 이동한다.
3. migration targeted tests를 통과시킨다.

완료 기준: `GRDBManager`와 공존하면서 새 AppDatabase가 fresh/fixture DB를 같은 최종 schema로 만든다.

### Step 3C. Record/mapper와 Message Store

1. Record와 mapper를 추가한다.
2. message save/read/pagination/search를 Message Store로 이동한다.
3. FTS strict rollback을 적용한다.
4. save/delete/prune transaction test를 추가한다.
5. `ChatMessageManager`, `ChatSearchManager`를 Protocol 주입으로 전환한다.

완료 기준: message/search 소비자가 `GRDBManager`를 참조하지 않고 transaction 회귀가 고정된다.

### Step 3D. Outbox와 Media Store

1. Outbox Protocol에서 message method를 분리한다.
2. Outbox Store와 Media Store를 추가한다.
3. Outbox UseCase에 두 persistence capability를 주입한다.
4. media repository pass-through 구현을 Store 직접 conformance로 교체한다.
5. outbox/media tests를 추가한다.

완료 기준: outbox와 media 소비자에 giant concrete dependency가 없다.

### Step 3E. Profile cache와 Room cleanup Store

1. Local user/cache Record와 mapper를 적용한다.
2. profile Store와 LRU transaction을 이전한다.
3. transient/exit cleanup Store를 이전한다.
4. exit cleanup에 outbox 삭제를 포함한다.
5. current user 보존과 orphan prune test를 추가한다.

완료 기준: profile/cleanup 소비자가 좁은 Protocol만 받고 room cleanup이 한 transaction이다.

### Step 3F. production DI와 giant façade 제거

1. `AppCompositionRoot`에서 AppDatabase를 한 번 생성한다.
2. AppCoordinator → ChatContainer → ChatPersistenceProvider로 전달한다.
3. Manager/UseCase/CompositionRoot가 provider capability를 명시적으로 받도록 바꾼다.
4. direct `.shared` default를 제거한다.
5. `GRDBManager.swift`와 pass-through GRDB repository 구현을 제거한다.
6. static reference 검색을 수행한다.

완료 기준: production과 test 조립이 같은 Store 경계를 사용하고 `GRDBManager` 참조가 0이다.

### Step 3G. 회귀 검증과 하네스 최신화

1. Phase 3 targeted tests 실행.
2. 기존 관련 Chat tests 실행.
3. generic Simulator build 실행.
4. 대표 수동 QA.
5. DATA/CHAT/TESTS/ENTRYPOINTS/task/HANDOFF 갱신.

## 테스트 계획

예상 test file, failure injection과 실행 명령은 [Phase 3 테스트 계획](phase-3-grdb-tests.md)을 따른다.

## 완료 기준

- migration 15개 순서와 최종 schema가 확정값과 같다.
- legacy GRDB roomImage/no-op migration/API가 없다.
- `AppDatabase`가 DatabasePool과 migration lifecycle만 소유한다.
- 소비자는 필요한 persistence Protocol만 받는다.
- message/FTS/media, deletion, prune, LRU, cleanup transaction tests가 통과한다.
- FTS 실패 시 partial message/media row가 남지 않는다.
- exit cleanup은 room outbox까지 제거하고 current user는 보존한다.
- `GRDBManager.swift`, `GRDBManager.shared`, concrete manager 주입이 없다.
- iOS build와 targeted tests가 통과한다.
- 서버와 배포 설정은 변경하지 않는다.

## 구현 결과

- 계획한 `AppDatabase`, migration registry/rebuilder, record/mapper, Store 5개와 `ChatPersistenceProvider`를 반영했다.
- 관련성이 높은 작은 타입은 `ChatPersistenceModels.swift`, `ChatProfileRecords.swift`, `ChatMediaIndexRecords.swift`처럼 같은 책임 파일에 묶어 계획보다 파일 수만 줄였다. Protocol/Store 경계와 transaction 소유권은 계획대로 유지했다.
- `GRDBManager.swift`, 기존 outbox 혼합 Protocol과 pass-through participants/media GRDB 구현을 제거했다.
- targeted test 10개 suite와 generic Simulator build가 통과했다.
- 화면 동작을 바꾸는 작업은 아니지만 실제 채팅 흐름 수동 QA는 아직 수행하지 않았다.

## Phase 4 전 후속 작업 구현 결과

- `AppDatabase.live()`의 production path/migration factory 역할은 유지한다.
- 내부 `fatalError`를 제거하고 `throws`로 초기화 오류를 `AppCompositionRoot` 이상에 전달한다.
- `try!`로 옮기는 방식은 금지한다.
- `AppCompositionRoot.makeCoordinator`는 database factory closure를 받고 `AppBootstrapError`로 mapping한다.
- `SceneDelegate`는 실패 시 독립 `AppBootstrapFailureViewController`를 root로 표시하고 수동 재시도를 제공한다.
- 알림 route는 bootstrap보다 먼저 저장하고 성공한 Coordinator만 보관한다.
- `--app-bootstrap-fail-database-once`, `--app-bootstrap-fail-database-always` DEBUG argument로 실제 DB 손상 없이 실패·복구 UI를 검증한다.
- Chat 제한 모드, 자동 재시도와 로컬 DB 초기화는 이 작업 범위에 포함하지 않는다.
- `AppBootstrapError`, `AppBootstrapFailureInjector`, `AppBootstrapFailureViewController`를 추가하고 위 경계를 구현했다.
- `MainTabBarController`에 UI 테스트용 `app.main.root` marker를 추가했다.
- D19 unit test 5개와 UI test 2개, generic Simulator build가 통과했다.

## 구현 중 중단 조건

- 승인된 D15 제거 외 table/column/index 변경이 필요하다.
- pagination 결과나 outbox file recovery 의미를 바꿔야 compile된다.
- Store 분리 때문에 기존 transaction을 쪼개야 한다.
- Firebase/Socket 계약 변경이 필요하다.
- 개발 DB 초기화 외 운영 데이터 migration이 필요하다는 사실이 발견된다.

중단 조건이 발생하면 범위를 확장하지 않고 사용자에게 선택지와 추천안을 보고한다.
