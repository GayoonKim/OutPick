# Data Entrypoints

**Q7 실제중단원장(2026-10-07):** K의3accepted/동일execution attempt1·batch143c...epoch49, consumedOOM1회, queue/batch/executionactive를보존했다. 부분writes6(당시unpublished4/uploading2)·객체12/384872B는완료산출물이아니다. assets부모문서가없을수있어실행기는bounded listDocuments로하위writes를조회한다. 서버cleanup예약·성공124JPEG·실패목록제거의원격확인은아직남았다. [결과·원본](../tasks/lookbook-import-performance/q7-retry-development-results.md).

**Q7 K/L 제어 원장(2026-10-07):** `lookbookImportQ7FaultCampaigns/{campaignID}`와 `/targets/{executionID}`는 서버 전용 Development 검증 데이터다. campaign/revision/digest/expiresAt20분·exact batch/job/execution·K consumedAt/원본 upload generation·L consumedAttempts1~5를 보존한다. 공개 API/IAM 추가 없음. 제품 접수8회와 제어 문서 쓰기는 별도 집계한다. asset cleanup은 run 종료 증거 또는90일 automaticTerminationRetry 감사로 exact project/batch/run을 검증하며 현재 참조/진행파일을 보호한다. Development 정리 스케줄러미배포·24시간 물리삭제는 미검증.

**Q7-R1 실패 목록(2026-10-07):** 서버 `seasonImportFailures`는 원본 실행 이력과 별도다. 실패 identity는 기존 importJobs sourceURL claim hash이고 최신 executionID+version으로 경합을 막는다. 진행/검토 문서는 보호하며 안 함의 `seasonImportFailureActions` receipt는30일, 실패 상세30일/종료 감사90일이다. run 종료 증거는 실제 drain 필드와 분리하고 restartPreparedAttempt는 같은 정리를 반복하지 않도록 준비된 시도를 표시한다. 부분 season/posts/assetFailures는 이번 job 소유·사용자 활동 없는 범위만 정리한다. [스키마](../DATA_SCHEMA.md), [구현 계약](../tasks/lookbook-import-performance/q7-retry-contract-plan.md).

**Q7 실행 증거와 데이터 경계(2026-10-06):** `tools/lookbook-import-worker/scripts/q7-runner.mjs`는 Development 제품 callable로 브랜드/discovery/import/review를 요청하고, `q7-journal.mjs`에 전송 전 요청을 원자 기록한다. 응답 불명확 상태는 재전송하지 않고 새 stage를 막는다. 결과 collector는 Firestore queue/batch/run/epoch/review와 exact Storage generation의 bytes/hash/JPEG 크기를 읽기 전용으로 대조한다. 현재 candidate만 준비됐고 새 QA 브랜드/Storage object는 아직 만들지 않았다. 실행 증거 위치와 예상 전송량은 [Q7 readiness](../tasks/lookbook-import-performance/product-queue-q7-readiness.md).

**Q6 queue 실행 원장 보강(2026-10-06):** batch item 시작 때 `queueActiveRunID`가 job root에 현재 run을 표시해 legacy claim 경로와 실행권을 대조한다. continuation은 최초 활성화 뒤 `activatedAt`을 기록해 같은 batch 재진입 시 도메인 상태를 다시 바꾸지 않는다. asset retry child job은 `queueActivatedForBatchID`로 동일 batch에서 재활성화를 구분하며 parent job/source claim을 보존한다. 세부 path/transaction 경계는 [DATA_SCHEMA](../DATA_SCHEMA.md#제품-fifo-import-실행-이력), [Q6 결과](../tasks/lookbook-import-performance/product-queue-q6-results.md).

**Q5 앱 요청 기록(2026-10-06):** GRDB `lookbookImportRequest(ownerUID,requestID)` migration27은 서버 FIFO 원장이 아니라 앱 재실행·응답 유실 시 같은 요청을 복구하기 위한 계정별 outbox/receipt다. 미확정은 보존하고 settled만 30일 뒤 정리한다. AppCompositionRoot에서 store/UID를 provider의 brand/discovery/import/retry/review/repair adapter에 주입한다. 계정 삭제 scrubber와 임시 DB tests는 G-I에서 검증한다. [Q5 결과](../tasks/lookbook-import-performance/product-queue-q5-results.md), [schema](../DATA_SCHEMA.md#제품-fifo-import-실행-이력).

**Q4 최신 데이터 상태(2026-10-05):** batch의 `retentionNextAt/receiptExpiresAt/detailsPruned/detailCleanupAfter`, `brandCreationRequests.receiptExpiresAt/retentionNextAt`, `recoveryDecisions.createdAt/expiresAt`을 Functions가 만료 정리에 사용한다. batch/brand 생성 receipt는 최소30일, 해결된 실패 상세30일, 복구 결정90일이며 현재 head·진행·검토·복구는 연장 보호한다. queue-owned write ledger는 uploading 동안 보호하고 terminal·미참조·24시간 후에만 exact generation으로 시간당 정리한다. 로컬 emulator만 검증했으며 원격 Firestore/Storage 삭제는 실행하지 않았다. [Q4 구현·게이트](../tasks/lookbook-import-performance/product-queue-q4-results.md), [schema](../DATA_SCHEMA.md#제품-fifo-import-실행-이력).

Q3 최신: queue image write는 `brands/{brandID}/importJobs/{jobID}/executions/{executionID}/assets/{assetKey}/writes/{writeID}`에 `uploading` 원장과 target scope/path를 업로드 전에 기록하고, 두 객체 generation·size 및 terminal 상태를 게시 시점에 기록한다. 삭제 함수는 `status=uploading` collection-group 조회로 정확한 post/season/brand 범위를 차단한다. `firestore.indexes.json`의 세 composite index가 필요하며 이 작업에서 배포하지 않았다. [Q3 구현·검증](../tasks/lookbook-import-performance/product-queue-q3-results.md).

## Lookbook product queue records

Q2/Q6 최신: `runs/{runID}.resourceEvidence`에는 cgroup 표본 수·최대 비율·출처·한도와 메모리/접수 중단/14분 drain 관측이 저장된다. 모든 지원 batch kind는 같은 owner/epoch 경계에서 활성화되며 retryable 시즌 오류는 즉시 최초 포함 총5회 재시도한다. 14분 응답 경계는 retryable 503 후 processor drain을 기다린다. 원격 Cloud Run 종료 증거는 없다.

- Firestore source/field rules: `docs/ai/DATA_SCHEMA.md`의 `제품 FIFO import 실행 이력`과 `docs/ai/entrypoints/FIREBASE.md`의 Q2 Worker 실행 기록.
- Worker transaction modules: `tools/lookbook-import-worker/src/queue/{coordinator,checkpoint,batch-runner,activation,supervisor,http-deadline}.ts`. Batch claim/run/progress와 execution attempt ledger를 owner/bootID/epoch fence로 쓴다. `activation.ts`가 discovery/import/retry/review/repair를 이어주고 `server.ts`가 14분 retryable 503·drain 대기를 제공한다.
- Local verification/result: `verification/lookbook-product-queue.json`, `firestore-tests/lookbook-import-queue.emulator.test.mjs`, [Q2 결과](../tasks/lookbook-import-performance/product-queue-q2-results.md).
- Functions Cloud Tasks sender/head trigger/reconciliation 및 각 지원 kind의 Worker activation은 로컬 구현·Emulator 검증됐다. legacy 경로의 실제 Development 차단, task 재전달, 실행별 asset 경로·조건부 공개와 active write deletion fence의 원격 동작은 Q7 확인 대상이다. 이 작업에서 Development/Production task를 보내지 않았다.

## 채팅 검색 임시 결과

[최종 데이터/API 계약](../architecture/CHAT_MESSAGE_SEARCH.md)을 기준으로 한다.

- ChatMessageSearchSession.swift → ChatSearchPersisting.swift → GRDBChatSearchStore.swift. ChatSearchSQL.swift의 26번째 migration(createChatSearchSessions)은 일반 캐시와 별도 session/hit/blockedAuthor 테이블을 생성한다. 본문·첨부를 복제하지 않고 ID·seq·작성자 metadata만 보관한다.
- commitPage는 accountEpoch/generation/visibilityRevision·기대 cursor 검사, 삭제/차단 배제, insert-ignore, cursor/소진 기록을 한 transaction으로 처리한다. insertedCount로 신규 결과 여부를 판정한다. count/ordinal은 현재 유효 행 기준이며 결과 조회는 최대 100개다.
- FirebaseChatSearchRepository의 opaque cursor는 세션·방·검색어·상한과 마지막 원본 후보(seq, ID)를 묶는다. 서버 source만 허용하고 cache/pending·잘못된 정렬·손상된 v2 projection을 거부한다.
- GRDBChatSearchLocalReader는 고정 DatabaseSnapshot의 seq 범위를 최대 100개씩 읽어 동일 Swift contains를 적용한다. LIKE 전량 배열 검색은 없다.
- GRDBChatDeletionSyncStore.messageIDs는 일반 캐시와 검색 전용 hit의 합집합을 최대 100개씩 복구한다. marker와 hit 제거는 원자적이다. requiresResolvedDeletionFence는 marker의 seq/revision/익명화/시각 및 잔존 hit를 비교해 중복 무효화를 막는다.
- AppDatabase 재시작·계정 삭제·ChatRoomCleanupSQL·검색 종료가 임시 결과를 정리한다. 일반 캐시 prune은 검색 hit를 지우지 않는다. ChatPersistenceProvider가 동일 DB의 searchStore/searchLocalReader를 제공한다.
- UserBlockVisibilityStore의 차단 집합은 세션 동안 누적하며 해제 후 신규 검색에서 복구한다. 삭제 write 완료/실패가 확인되기 전 공개를 보류한다. 주변 본문은 anchor+전후 60개, 선택 제거 시 neighbor로 확보된 인접 metadata 1개를 찾는다.

## 채팅 미디어 만료 계약

- 서버 contract 3 확정이 `sentAt`, `mediaExpiresAt = sentAt + 168시간`, `attachmentID`, 원본·썸네일 bucket/path/generation을 생성한다. 메시지·mediaIndex·delivery 응답·답장 preview에 필요한 계약을 전달한다.
- `ChatMessage`/`Attachment`/`ReplyPreview`/`ChatRoomMediaIndexEntry`와 GRDB record·mapper·migration이 이 필드를 보존한다. 재로그인·다운로드·캐시 hit로 기한을 연장하지 않는다.
- `chatMediaExpiryJobs/{hash(roomID,messageID)}`는 서버 전용 작업이다. 상태는 scheduled/processing/awaitingEvidence이며 전체 삭제 성공 시 문서를 제거한다. 완료 이력 문서를 별도로 만들지 않는다.
- `ChatMediaExpiryCacheIndex`는 계정과 객체 generation·만료 시각을 디스크 리소스에 연결한다. 서명 URL은 영구 저장하지 않는다.
- [최종 데이터/API 계약·검증](../architecture/CHAT_MEDIA_RETENTION.md).


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
