# GRDB Contract Inventory

## Phase 1 조사 당시 경계

- 진입점: `OutPick/DB/GRDB/GRDBManager.swift`.
- 기본 DB: Documents의 `OutPick.sqlite`, `DatabasePool` 사용.
- 책임: DB 생성, migration, message/FTS, outbox, media index, profile cache, room cleanup.
- 테스트 주입: `init(dbPool:)`로 임시 `DatabasePool` 사용 가능.
- 기존 좁은 계약: `ChatOutgoingOutboxPersisting`; 기능별 Store 전환의 선행 사례다.

## migration identifier와 순서

아래 문자열과 등록 순서는 Phase 1 조사 시점의 역사적 기준선이다. Phase 3에서 4개 legacy identifier를 제거했다.

1. `foreignKeysOn`
2. `createLocalChatUser`
3. `createRoomProfileDisplayCache`
4. `createUserProfile` — legacy no-op
5. `addThumbAndOriginalToUserProfile` — legacy no-op
6. `createChatMessage`
7. `addSeqToChatMessage`
8. `migrateChatMessageSenderUID`
9. `createChatMessageFTS`
10. `addReplyPreviewToChatMessage`
11. `addIsDeletedToChatMessage`
12. `addSenderAvatarPathToChatMessage`
13. `addLookbookShareToChatMessage`
14. `rebuildChatMessageSenderUIDSchema`
15. `createRoomParticipant` — legacy no-op
16. `createRoomImage`
17. `createImageIndex`
18. `createVideoIndex`
19. `createChatOutgoingOutbox`

초기 조사 요약의 18개는 `foreignKeysOn`을 제외한 schema migration 수였다. Phase 1 실제 등록 identifier 기준선은 위 19개다.

### Phase 3 현재 구현

- D15에 따라 no-op `createUserProfile`, `addThumbAndOriginalToUserProfile`, `createRoomParticipant`와 legacy `createRoomImage`를 제거한다.
- fresh DB 목표 migration은 나머지 순서를 유지한 15개다.
- 앱이 아직 배포되지 않았으므로 기존 설치 DB 호환용 drop migration은 만들지 않고 개발 앱 DB를 초기화한다.
- 현재 production source는 이 15개 기준선을 사용한다. Phase 1의 19개 목록은 변경 전 계약 비교용으로만 남긴다.

## Phase 1 schema 기준선

| table | columns | key/index |
| --- | --- | --- |
| `LocalChatUser` | `userID`, `nickname`, `profileImagePath?` | PK `userID`; `idx_LocalChatUser_nickname` |
| `RoomProfileDisplayCache` | `roomID`, `userID`, `lastSeenAt`, `lastMessageSeq?`, `lastMessageID?`, `updatedAt` | PK `(roomID,userID)`; room/room-LRU/user index; user FK cascade |
| `chatMessage` | `id`, `seq`, `roomID`, `senderUID`, `senderEmail?`, `senderNickname`, `senderAvatarPath?`, `messageType?`, `msg?`, `sentAt?`, `attachments?`, `sharedContent?`, `isFailed`, `replyPreview?`, `isDeleted` | PK `id`; `(roomID,sentAt)`, `(roomID,seq)` index |
| `chatMessageFTS` | `msg`, `roomID`, `id` | FTS5; `id` not indexed |
| `roomImage` | `roomId`, `imageName`, `uploadedAt` | PK `(roomId,imageName)` |
| `imageIndex` | room/message/index, key/URL, size/hash/failure/local thumb/sent time fields | PK `(roomID,messageID,idx)`; room-sentAt/messageID index |
| `videoIndex` | image index fields + `duration?`, `approxBitrateMbps?`, `preset?` | PK `(roomID,messageID,idx)`; room-sentAt/messageID index |
| `chatOutgoingOutbox` | `messageID`, `roomID`, `kind`, `stage`, timestamps, local/uploaded JSON?, `lastError?` | PK `messageID`; `(roomID,updatedAt)` index |

`rebuildChatMessageSenderUIDSchema`는 legacy `senderID`가 남아 있을 때 table을 재생성하고 `senderUID`를 backfill한다. 이 조건, 데이터 필터, index 재생성은 migration 회귀 기준이다.

## operation과 목표 Store

| 현재 operation 묶음 | 핵심 method | 현재 소비자 | 목표 계약/구현 |
| --- | --- | --- | --- |
| message write/read | `saveChatMessages`, fetch recent/before/after/older/newer/all, count, single fetch | `ChatMessageManager` | `ChatMessagePersisting` / `GRDBChatMessageStore` |
| message state/cleanup | failed fetch, hard delete, deleted/reply update, prune, room delete | `ChatMessageManager`, transient cleaner | message capability + cleanup capability |
| search | `fetchMessages` FTS | `ChatSearchManager` | `ChatMessageSearching` / message Store |
| outbox | save/fetch/delete outbox | `ChatOutgoingOutboxUseCase` | 기존 `ChatOutgoingOutboxPersisting` / `GRDBChatOutgoingOutboxStore` |
| media index | image/video fetch/count/page/upsert/delete/duration | `GRDBChatRoomMediaIndexRepository` | `ChatMediaIndexPersisting` / `GRDBChatMediaIndexStore` |
| profile cache | local user upsert/fetch, room display cache, count/evict | participants repository, profile sync, message manager | `ChatProfileCachePersisting` / `GRDBChatProfileCacheStore` |
| room cleanup | room의 message/FTS/media/outbox/cache 삭제와 orphan user prune | room exit/transient cleanup | `ChatRoomLocalDataCleaning` / `GRDBChatRoomLocalDataStore` |
| legacy room image | `addImage`, `fetchImageNames`, `deleteImages` | `deleteImages`는 transient cleaner가 호출하고 add/fetch 소비자는 없음 | D15에 따라 API/table 제거, cleaner는 message/media cleanup Store로 전환 |

## 보존해야 할 transaction 경계

### 메시지 저장

한 `dbPool.write` 안에서 각 message에 대해 다음을 수행한다.

1. `chatMessage` upsert.
2. `chatMessageFTS` upsert.
3. 해당 message의 기존 `imageIndex`/`videoIndex` 정리.
4. attachment 기반 media index 재구성.

현재 구현은 FTS 오류를 내부에서 삼켜 message/media만 commit될 수 있다. D18은 이를 보존하지 않고 오류를 전파해 message/FTS/media 전체를 rollback하도록 의도적으로 변경한다. 보존 개수 prune은 현재 호출 시점과 결과를 characterization test로 고정한다.

### 단일·대량 삭제

- `hardDeleteMessage`: `chatMessage`, `imageIndex`, `videoIndex`, FTS 삭제를 한 write로 처리한다.
- `pruneMessages`: 제거 ID 선택과 관련 projection 및 message 삭제를 한 write로 처리한다.
- room exit cleanup: room의 message/FTS/media/outbox/profile cache를 삭제한 후 같은 write에서 orphan `LocalChatUser`를 prune한다. 현재 구현에서 누락된 outbox 삭제는 D16에 따라 보완한다.
- transient cleanup: message/FTS/media만 같은 write에서 삭제하고 outbox/profile cache는 보존한다.

### profile display cache

- cache upsert와 room별 LRU 20명 eviction은 같은 write에서 수행한다.
- current user 보존과 정렬 기준은 기존 동작을 유지한다.

## 공통 DB와 DI 목표

- `AppDatabase`: `DatabasePool` 생성/보관과 read/write 접근만 소유한다.
- `GRDBMigrationRegistry`: D15 적용 후 15개 identifier/order/schema 등록을 소유한다.
- 기능 Store는 같은 `AppDatabase`를 주입받아 필요한 SQL과 mapping만 소유한다.
- `ChatContainer`, `ChatCompositionRoot`, `ChatManagerProvider`가 Store/Protocol을 조립한다.
- `ChatMessageManager`의 message와 profile cache 의존은 서로 다른 capability로 분리한다.
- 여러 table을 원자적으로 다루는 room cleanup은 개별 Store 호출 조합이 아니라 전용 Store가 transaction을 소유한다.

## Phase 3 회귀 기준

- fresh DB는 D15의 15개 migration과 `roomImage`가 없는 목표 schema에 도달한다.
- 개발 DB 초기화 정책을 사용하므로 제거된 4개 identifier를 포함한 기존 migration fixture 호환은 Phase 3 완료 기준에서 제외한다.
- 유지하기로 한 15개 identifier/order와 schema는 변경하지 않는다.
- message/FTS/media, hard delete, prune, room cleanup, profile LRU 원자성을 테스트한다.
- FTS 실패와 room exit 중간 실패가 전체 transaction을 rollback하는지 검증한다.
- 소비자는 `DatabasePool`이나 giant manager가 아니라 필요한 persistence Protocol만 받는다.
- phase 종료 시 `GRDBManager` giant façade를 제거한다.
