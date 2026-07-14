# Phase 3 GRDB Decisions

## 상태

2026-07-13 사용자 승인으로 N3~N5와 FTS 실패 정책을 확정했고 Phase 3 구현·자동 검증을 완료했다. D19는 Phase 4 코드 구현 전에 처리할 Phase 3 후속 안정화 결정이다.

## D15. 운영 배포 전 legacy GRDB 경계를 clean break로 제거한다

- 앱은 아직 운영 배포되지 않았으므로 기존 사용자 DB migration 호환성을 유지할 필요가 없다.
- `createRoomImage` migration, `roomImage` table과 `addImage`/`fetchImageNames`/`deleteImages` API를 제거한다.
- 빈 migration인 `createUserProfile`, `addThumbAndOriginalToUserProfile`, `createRoomParticipant`도 제거한다.
- migration 기준선은 현재 19개에서 15개로 바뀐다.
- 기존 개발 Simulator/기기는 앱 삭제·재설치 또는 앱 데이터 초기화로 새 baseline을 적용한다.
- `dropRoomImage` migration은 추가하지 않는다. legacy 이력을 새 registry에 다시 남기지 않기 위해서다.
- Firebase Storage의 `MediaStorageLocation.roomImage`, `RoomImageService`, 채팅방 대표 이미지 기능은 이름만 같을 뿐 GRDB table과 무관하므로 유지한다.

## D16. 소비자 Protocol과 횡단 transaction owner를 분리한다

- 소비자는 자신이 사용하는 persistence capability만 주입받는다.
- `AppDatabase`는 `DatabasePool` 생성·수명·migration 실행만 담당하고 기능 SQL이나 transaction orchestration을 소유하지 않는다.
- 여러 table을 함께 변경하는 작업은 작업 단위 Store 한 곳이 하나의 `DatabasePool.write`를 소유한다.

확정 owner:

| 원자적 작업 | owner |
| --- | --- |
| message 저장 + FTS + image/video projection | `GRDBChatMessageStore` |
| 삭제 표시 + reply preview 갱신 + media projection 삭제 | `GRDBChatMessageStore` |
| hard delete와 prune의 message/FTS/media 정리 | `GRDBChatMessageStore` |
| outbox row CRUD | `GRDBChatOutgoingOutboxStore` |
| 독립 media query/upsert/row delete/duration update | `GRDBChatMediaIndexStore` |
| local user와 room profile cache upsert + LRU eviction | `GRDBChatProfileCacheStore` |
| transient room cleanup과 exit cleanup + orphan user prune | `GRDBChatRoomLocalDataStore` |

- Store끼리 public API를 연쇄 호출해 transaction을 흉내 내지 않는다.
- 공통 SQL이 필요하면 같은 GRDB 구현 경계 안의 `internal` helper를 사용하되 transaction owner는 하나만 둔다.
- exit cleanup은 message/FTS/media/outbox/profile cache를 같은 write에서 삭제하고 current user를 제외한 orphan local user를 prune한다.
- transient cleanup은 기존 의미를 유지해 message/FTS/media만 삭제하고 outbox/profile cache는 유지한다.

## D17. persistence Record는 선택적으로 분리한다

- 새 schema는 만들지 않는다.
- Domain 표현과 DB column 표현이 실제로 다른 타입부터 Record와 mapper를 분리한다.
- `ChatMessageRecord`는 JSON string column인 attachments/sharedContent/replyPreview와 DB scalar를 소유하고 `ChatMessageRecordMapper`가 `ChatMessage`와 변환한다.
- `LocalChatUser`는 Chat/UI model로 유지하고 `LocalChatUserRecord`만 GRDB conformance를 가진다.
- `RoomProfileDisplayCacheRecord`, `ImageIndexRecord`, `VideoIndexRecord`는 persistence-only type으로 둔다.
- 기존 소비자가 사용하는 `ImageIndexMeta`, `VideoIndexMeta`는 read model로 유지하고 내부 Record에서 mapping한다.
- `ChatOutgoingOutboxRecord`는 이미 persistence 계약을 드러내므로 같은 의미의 Domain/DB type을 이중으로 만들지 않는다.
- JSON encode 실패 fallback은 기존 동작을 유지한다: attachments는 `[]`, optional reply/shared content는 `nil`.
- 필수 식별자가 잘못된 message만 건너뛰는 기존 batch 정책과 3,300개 초과 시 3,000개로 prune하는 정책을 유지한다.

## D18. FTS 실패는 message transaction 전체를 rollback한다

- 현재 구현은 FTS insert 실패를 catch 후 삼켜 message와 media만 commit할 수 있다.
- Phase 3에서는 FTS 오류를 전파한다.
- message row, FTS, image/video projection 중 하나라도 실패하면 같은 write 전체를 rollback한다.
- 이는 구조 이동만이 아니라 실패 동작의 의도적 수정이다.
- 이유는 로컬 message와 검색 projection의 불일치를 조용히 남기는 것보다 실패를 호출자에게 전달해 재시도·관찰 가능하게 하는 편이 안전하기 때문이다.
- transaction rollback test에서 강제로 FTS 실패를 만들고 message/media row가 남지 않는지 검증한다.

## D19. `AppDatabase.live()` 초기화 실패는 `throws`로 호출자에게 전달한다

- production DB 경로와 migration 조립을 `AppDatabase.live()`에 모으는 현재 factory 방향은 유지한다.
- `live()` 내부의 `fatalError`는 제거하고 `static func live() throws -> AppDatabase`로 변경한다.
- `AppCompositionRoot.makeCoordinator(window:makeDatabase:) throws`가 database factory 오류를 `AppBootstrapError.localDatabaseInitializationFailed`로 변환한다.
- 기본 database factory는 `AppDatabase.live`이며, test에서는 실패 closure를 주입할 수 있다.
- `SceneDelegate`가 `do/catch` 최종 경계가 되어 성공한 `AppCoordinator`만 보관한다.
- `try!`, `try?` 또는 CompositionRoot의 다른 `fatalError`로 단순 치환하면 의미가 없으므로 사용하지 않는다.
- 초기화 실패 시 앱 일부를 조립하지 않고 DB에 의존하지 않는 `AppBootstrapFailureViewController`를 root로 표시한다.
- 실패 화면은 일반 사용자 문구와 `다시 시도`만 제공한다. raw GRDB/SQLite 오류와 파일 경로는 표시하지 않는다.
- 재시도는 같은 앱 process에서 CompositionRoot 전체 조립을 다시 시도하고, 성공 시 정상 `AppCoordinator.start` 흐름으로 전환한다.
- 자동 재시도, Chat 제한 모드와 로컬 DB 초기화 버튼은 범위에서 제외한다. Outbox 유실 가능성이 있는 데이터 삭제는 별도 사용자 결정 없이 수행하지 않는다.
- pending notification route는 DB 초기화보다 먼저 저장해 최초 조립 실패 후 재시도에서도 보존한다.
- underlying error는 OSLog의 bootstrap category에 privacy를 지켜 기록한다.
- 동기 DB 생성/migration 실행 방식은 현재 동작을 유지하며 이번 후속 작업에서 background initialization으로 확장하지 않는다.
- DEBUG 전용 `--app-bootstrap-fail-database-once`는 최초 database factory 호출만 실패시키고 같은 process의 재시도는 성공시킨다.
- DEBUG 전용 `--app-bootstrap-fail-database-always`는 모든 재시도를 실패시켜 반복 실패 화면과 scene lifecycle을 검증한다.
- failure injection은 `AppDatabase`와 실제 SQLite 파일을 변경·삭제하지 않고 Release 빌드에서는 동작하지 않는다.
- 이 변경은 Phase 4 Firebase Functions 코드 구현 전에 별도 승인으로 구현·검증한다.

## 선택하지 않은 대안

- legacy migration/table을 유지하는 방식: 운영 사용자 DB가 없으므로 불필요한 호환 비용이다.
- 호출자가 여러 Store method를 조합하는 방식: 중간 실패 시 partial commit 위험이 있다.
- `AppDatabase`가 모든 기능 operation을 소유하는 방식: 이름만 바뀐 giant manager가 된다.
- 모든 Domain type을 일괄 Record로 복제하는 방식: 단순 type까지 mapper가 늘어 Phase 범위가 과도해진다.
- FTS best-effort 유지: 검색 누락을 성공으로 취급하게 된다.
- `AppDatabase.live()` 내부 fail-fast 유지: infrastructure factory가 앱 종료 정책까지 소유하고 초기화 실패를 테스트·복구하기 어렵다.
- Chat 제한 모드: Chat persistence optionality가 AppCoordinator, tab, 로그인 bootstrap, 공유와 알림까지 퍼져 D19 범위를 벗어난다.
- 로컬 DB 자동/사용자 초기화: 전송 대기 Outbox 유실 가능성이 있어 실제 필요와 데이터 정책을 별도로 확인해야 한다.

## 재검토 조건

- 첫 운영 배포 이후에는 migration identifier 제거·순서 변경을 금지하고 append-only migration 정책으로 전환한다.
- 다른 feature가 같은 AppDatabase를 사용하게 되면 Store module/target 경계와 database access visibility를 재검토한다.
- media projection이 message transaction과 독립적으로 재생성되는 요구가 생기면 projection rebuild service를 별도 설계한다.
