# OutPick Data Schema Index

## 목적과 읽기 순서

이 문서는 데이터 계약의 상위 인덱스다. 필드 전체를 중복 기록하지 않고 변경 목적에 맞는 source of truth로 연결한다.

1. 도메인 코드 위치: `docs/ai/ENTRYPOINTS.md`
2. 앱/Repository 경계: `docs/ai/entrypoints/DATA.md`와 기능별 entrypoint
3. Firestore/Functions/Storage: `docs/ai/entrypoints/FIREBASE.md`
4. 중요한 선택 이유: `docs/ai/ADR.md`
5. 현재 구현·검증 상태: `docs/ai/tasks/active.md`와 해당 task `progress.md`

## 공통 원칙

- Firebase, Firestore, Cloud Functions, GRDB, Storage는 View가 직접 접근하지 않는다.
- Domain entity와 외부 DTO를 분리하고 mapper가 변환을 담당한다.
- Firestore 문서의 자기 identity는 ADR-020에 따라 문서 경로 ID를 사용하고 payload에 `ID`/`id`로 중복 저장하지 않는다.
- ViewModel은 Repository/UseCase 계약에 의존한다.
- 확정되지 않은 collection, field, index는 추가하지 않고 사용자와 논의한다.
- 실제 보안 계약은 `firestore.rules`, query 계약은 `firestore.indexes.json`, Storage 계약은 `storage.rules`가 최종 source다.

## 도메인별 데이터 지도

| 도메인 | 핵심 source | 코드/상세 진입점 |
| --- | --- | --- |
| 인증·사용자 | Firebase Auth UID, `users/{uid}`, `userPublicProfiles/{uid}` | ADR-021, [FIREBASE](entrypoints/FIREBASE.md), [DATA](entrypoints/DATA.md) |
| Chat room/membership | `Rooms/{roomID}`, `Rooms/{roomID}/members/{uid}`, `users/{uid}/joinedRooms/{roomID}` | [CHAT](entrypoints/CHAT.md), ADR 관련 task |
| Chat message/cache | `Rooms/{roomID}/Messages/{messageID}`, GRDB `chatMessage`, `LocalChatUser`, `RoomProfileDisplayCache` | [CHAT](entrypoints/CHAT.md), [DATA](entrypoints/DATA.md) |
| UGC safety/moderation | `moderationPrincipals`, `moderationPrincipalAliases`, `moderationAccounts`, `moderationUserReports`, `moderationRoomReports`, `moderationAuditLogs`, `moderationCommentWriteRateLimitBuckets`, room `bans` | [계약](../../contracts/chat-moderation-v1.json), ADR-024, [CHAT](entrypoints/CHAT.md), [FIREBASE](entrypoints/FIREBASE.md) |
| Lookbook | `brands/{brandID}/seasons/{seasonID}/posts/{postID}` | [LOOKBOOK](entrypoints/LOOKBOOK.md) |
| 브랜드 관리 | `brandAdmins/{uid}`, `brands/{brandID}/admins/{uid}` | [LOOKBOOK](entrypoints/LOOKBOOK.md), [FIREBASE](entrypoints/FIREBASE.md) |
| 스타일 무드 | `styleMoods`, `styleMoodTermIndex`, `styleMoodSeedMetadata` | [FIREBASE](entrypoints/FIREBASE.md), ADR-022 |
| 브랜드 요청 | `brandRequests`, `brandRequestNameIndex`, daily counter/user limit | [FIREBASE](entrypoints/FIREBASE.md) |
| 시즌 import/discovery | `seasonDiscoveryJobs/{jobID}/candidates`, `seasonDiscoveryJobs/{jobID}/reviews`, `importJobs`, `lookbookExtractionDiagnostics` | [worker architecture](architecture/LOOKBOOK_IMPORT_WORKER.md) |
| 룩북 삭제 | `lookbookDeletionRequests`, `lookbookDeletionAuditLogs`, `lookbookDeletionPurgeLeases` | 아래 계약, [FIREBASE](entrypoints/FIREBASE.md), ADR-018 |

## 인증과 사용자 식별

- canonical user key는 Firebase Auth `uid`다.
- 앱 콘텐츠의 작성자·membership·공개 프로필 identity는 계속 Firebase Auth UID를 사용한다. 탈퇴·재가입 뒤 제재와 room ban을 복원하는 안전 identity만 canonical `moderationPrincipalID`를 사용하며 일반 콘텐츠 문서 ID를 대체하지 않는다.
- 문서상 `userID == canonicalUserID == Firebase Auth uid`다.
- 비공개 계정 경로는 `users/{uid}`, 앱 내 공개 프로필 경로는 `userPublicProfiles/{uid}`다.
- 이메일/provider fallback query는 사용하지 않고 관리자 이메일 조회는 Firebase Auth를 사용한다.
- `Rooms.creatorUID`, `Messages.senderUID`, member 문서 ID, joinedRooms owner 경로는 같은 UID를 저장한다.
- Chat room 자기 identity는 `Rooms/{roomID}` 경로의 document ID이며 `ChatRoom.id`로 주입한다. 새 room payload에는 자기 `ID`/`id`를 저장하지 않는다.
- 2026-07-14 운영 Rooms의 legacy 자기 `ID` 4건을 cleanup했으며 사후 감사 기준 `Rooms.ID`/`Rooms.id` 보유 문서는 0건이다.
- `Rooms.participantUIDs`, 사용자 문서의 legacy `joinedRooms` 배열, `roomStates`는 신규 source로 사용하지 않는다.
- GRDB `LocalChatUser.userID`, `RoomProfileDisplayCache.userID`, `chatMessage.senderUID`도 같은 UID 의미다.
- 개발 DB에서 재현된 legacy `chatMessage.senderID NOT NULL` schema만 migration으로 현재 schema로 재작성한다.
- 현재 구현은 앱 미배포 clean break를 적용한 fresh 19개 migration이다. Phase 7.3은 `chatOutgoingOutbox`에 upload identity·processing 상태·terminal/expiry·재시도용 session identity를 추가한다. signed PUT URL·필수 header 같은 bearer credential은 로컬 DB에 저장하지 않는다. legacy no-op 3개와 `createRoomImage`/`roomImage` table/API는 제거했으며 Phase 3 이전 개발 DB는 앱 삭제·재설치로 초기화한다.
- 메시지 저장 중 FTS 오류는 삼키지 않고 message/FTS/media transaction 전체를 rollback한다. 상세 결정은 `docs/ai/tasks/core-infrastructure-modularization/decisions/phase-3-grdb.md`를 따른다.

### 비공개 계정과 공개 프로필

- `users/{uid}`: `onboardingVersion`, `selectedMoodIDs`, `accountStatus`, 완료/생성/수정 timestamp만 저장한다. 본인 read, client write 금지다.
- `userPublicProfiles/{uid}`: `nickname`, nullable avatar thumb/original path, 생성/수정 timestamp만 저장한다. signed-in read, client write 금지다.
- `nicknameIndex/{sha256(normalizedNickname)}`는 서버 전용이며 UID와 timestamp만 저장한다.
- legacy `userIdentities`는 현재 앱·Functions에서 사용하지 않는다. Phase 10 개발 데이터 전체 초기화에서 전량 삭제하고 0건을 검증하되, Firestore Rules의 명시적 deny는 유지한다.
- nickname은 NFKC/trim/공백 축약/case-insensitive key를 사용하고 길이는 2~20자다.
- 온보딩 관심 무드는 고유한 active 무드 1~5개다.
- 계정/공개 프로필 생성과 nickname 변경은 Functions transaction만 사용한다.
- Storage avatar 쓰기는 active 계정만 가능하므로 신규 온보딩은 계정 생성 후 avatar를 업로드하고 공개 프로필을 갱신한다.
- 프로필 편집의 avatar mutation은 유지·새 경로 설정·명시적 제거를 구분한다. 교체는 새 객체 업로드 → 공개 프로필 경로 변경 → 이전 객체 삭제 순서이며, 제거는 공개 경로를 null로 변경한 뒤 이전 객체를 삭제한다.
- 공개 프로필 경로 변경 뒤 Storage 정리가 실패하면 삭제 대상 경로를 로컬 cleanup store에 보존하고 다음 마이페이지 진입에서 재시도한다.
- 현재 세션, Chat 참여자·sender, Lookbook 댓글 작성자, 사용자 상세는 `UserPublicProfile`을 직접 소비하며 legacy `UserProfile` 호환 모델은 사용하지 않는다.
- 상세 결정: ADR-021과 현재 task `data-api-contract.md`.

## Chat 핵심 계약

### Moderation identity와 capability

- `users/{uid}.accountStatus`는 기존 `active | deletionPending` 계정 생명주기만 소유한다.
- `moderationPrincipals/{moderationPrincipalID}`는 장기 제재의 canonical 원장이고 `moderationStatus: active | restricted | suspended`, `restrictedUntil`, `stateVersion`을 가진다.
- `moderationPrincipalAliases/{aliasID}`는 versioned HMAC alias를 principal에 연결한다. alias ID 형식은 `v{keyVersion}_{base64urlHmac}`이며 원본 provider subject·email·token을 저장하지 않는다.
- `moderationAccounts/{uid}` schema v2는 현재 UID의 `accountStatus`, principal, `moderationStatus`, `restrictedUntil`, `stateVersion`을 Rules·Functions·Socket·Storage가 한 번에 읽는 서버 전용 capability projection이다. `users/{uid}.accountStatus`는 사용자 계정 데이터의 원본으로 유지하되, 권한 판정 hot path에서는 이 projection만 사용한다.
- restricted 사용자는 read·report·block/unblock·자기 UGC 삭제·지원·계정 삭제만 허용하고, suspended 사용자는 제재 안내·지원·계정 삭제만 허용한다.
- `getMyModerationState.supportURL`은 운영 고객지원 경로 주입 전에는 `null`이며, 클라이언트는 값이 있을 때만 외부 고객지원 action을 노출한다.
- exact 필드와 capability matrix는 `contracts/chat-moderation-v1.json`, 선택 이유는 ADR-024를 따른다.

### 신고·audit

- 사용자 신고 aggregate: `moderationUserReports/{targetModerationPrincipalID}`.
- 방 신고 aggregate: `moderationRoomReports/{roomID}`.
- 사건별 신고는 각 aggregate의 `submissions/{submissionID}`, 고유 신고자 dedupe는 `reporters/{reporterModerationPrincipalID}`에 저장한다. aggregate에 무제한 reporter·room 배열을 두지 않는다.
- aggregate의 누적 통계와 관리자 `reviewState`를 분리한다. terminal 상태 뒤 새 사건은 `reviewState=open`, `reviewRevision + 1`, `caseVersion + 1`로 전환한다.
- `caseVersion`은 신고 횟수가 아니라 관리자 optimistic concurrency version이다.
- 메시지 신고는 전용 `submitMessageReport`가 먼저 `moderationMessageReportPreparations/{preparationID}`와 request별 `requests/{submissionID}`, server-only guard/bundle/job을 `processing`으로 만든다. request receipt는 응답 유실 뒤 같은 clientRequestID의 원래 결과를 보존하고, preparation은 새 clientRequestID 재시도가 같은 reporter/message/revision의 결정적 bundle을 재사용하게 한다. 제한된 text snapshot 또는 전체 media evidence가 `available`이 된 뒤에만 canonical `moderationMessageIncidents/{incidentID}`, review revision별 reporter 문서와 작성자 aggregate의 `reportedMessages/{incidentID}`·`messageReporters/{reporterID}` marker를 확정한다. processing/failed는 신고 count·queue·작성자 패턴·visibility에 포함하지 않는다. `submitUserReport`는 프로필/참여자 사용자 신고로 유지하며 attachment를 받지 않는다.
- 같은 `clientRequestID` 재전송은 revision-independent 최상위 receipt에서 기존 processing/accepted/failed 결과를 반환하고 transport quota를 다시 소비하지 않는다. 앱은 한 신고 시도의 최초 UUID를 terminal 결과까지 유지한다. 새 `clientRequestID`로 같은 reporter/message/review revision을 다시 신고하면 transport receipt slot 1개를 소비하며, processing 중에는 기존 결정적 bundle을 재사용하고 accepted 뒤에는 `alreadyReported`만 반환하며 failed cleanup 뒤에는 새 준비를 허용한다. evidence drain은 preparation별 `initialRequestID` receipt만 직접 확정하고 나머지 processing alias receipt는 같은 UUID 재조회 시 preparation의 terminal generation 결과로 한 건씩 수렴시켜 transaction 크기를 제한한다. moderation count·evidence는 중복 증가시키지 않는다.
- `moderationConfirmedViolations/{targetModerationPrincipalID}`와 `incidents/{actionID}`은 관리자 확정 위반만 기록한다. 최근 90일 count와 활성 경고는 관리자 판단용 projection이며 신고 접수만으로 증가하지 않고 자동 제재를 만들지 않는다.
- 텍스트 snapshot은 최대 4000 UTF-8 bytes로 제한한다. Phase 7 메시지 신고는 attachment 선택이나 동영상 시점 입력 없이 이미지 묶음의 정규화 `display` 전체 또는 동영상 정규화 원본 전체 1개를 결정적 evidence bundle로 복사한다.
- `moderationAuditLogs/{actionID}`는 서버 append-only이며 actor, action, bounded before/after, reason, report reference와 request ID를 기록한다.
- `moderationReportRateLimitBuckets/{principalID_minute}`는 같은 submission dedupe 뒤에만 증가하는 사용자 신고 burst counter다. principal당 UTC 1분 10건만 제한하며 일/대상별 hard cap은 두지 않는다.
- `moderationAdminRateLimitBuckets/{actorUID_kind_minute}`는 관리자 read/mutation burst counter다. 두 rate collection은 server-only이고 detail·message snapshot·provider identity를 저장하지 않으며 `expiresAt` TTL 2일을 사용한다.
- `moderationCommentWriteRateLimitBuckets/{principalID_utcMinute}`는 댓글·답글을 합산하는 server-only burst counter다. canonical principal당 UTC 1분 20건이며 `count`, `minuteBucket`, `updatedAt`, `expiresAt`만 저장하고 본문·post/comment/reply ID와 provider identity를 저장하지 않는다. post의 comment document ID는 `SHA-256(moderationPrincipalID + ":" + operation + ":" + clientRequestID)`로 결정하며, 같은 ID의 author·parent·message가 일치하는 replay는 counter를 소비하지 않고 불일치는 `IDEMPOTENCY_CONFLICT`다. `expiresAt` TTL 2일을 사용한다.
- 댓글·답글 본문은 trim 이후 UTF-16 code unit 1,000을 상한으로 하며 iOS도 `String.UTF16View.count`로 동일하게 계산한다. `clientRequestID`는 네트워크 retry 동안만 유지하고 입력 수정·취소·성공 후 새 작성에는 새 UUID를 사용한다.
- 신고·audit·principal·room ban의 Production TTL은 개인정보 보존 기간 승인 전 활성화하지 않는다. evidence는 기각·삭제만·경고만이면 처리 직후 cleanup을 enqueue하고 계정 제재 근거면 30일 이의제기 계약을 적용한다. 만료·실패 quarantine cleanup은 별도 운영 안전장치다.

### Phase 6 텍스트 메시지 개인정보·limiter 계약

- 신규 `Rooms/{roomID}/Messages/{messageID}`와 Socket/FCM/iOS/GRDB message projection은 `senderUID`와 필요한 공개 표시 snapshot만 사용하고 `senderEmail`을 저장·전송하지 않는다. 클라이언트가 제출한 email은 권위 값으로 사용하지 않는다.
- Socket process-memory bucket은 durable data가 아니다. key는 `moderationPrincipalID + roomID + messageKind`, value는 2초 window timestamps와 최근 계산한 message ID이며 60초 idle TTL·30초 sweep·50,000 active bucket cap을 갖는다. deploy/restart 초기화는 메시지 원장이나 멱등성 source를 변경하지 않는다.
- Socket message 중복의 최종 원장은 기존 Firestore message transaction이다. 메모리의 최근 message ID는 같은 process retry가 quota를 중복 소비하지 않게 하는 짧은 최적화일 뿐 durable idempotency record가 아니다.
- 모든 UGC는 자동 의미 필터나 외부 moderation provider 저장소를 만들지 않는다. 현재 댓글·답글 생성은 `attachments: []`인 텍스트 전용이고, 이미지·동영상 채팅만 Phase 7의 quarantine/technical-validation metadata를 사용한다.

### 메시지 삭제·room ban·방 lifecycle

- 메시지 삭제는 서버 API만 수행한다. `Messages/{messageID}.isDeleted`와 seq tombstone은 유지하고 공개 payload·attachments·reply/announcement/room summary·media index·Storage는 idempotent cleanup으로 정리한다.
- `chatMessageCleanupJobs/{sha256(roomID:messageID)}`는 reply preview·media index·고정 message Storage prefix를 재시도한다. completed는 7일 TTL, 20회 실패는 TTL 없이 남긴다.
- 방 종료는 `active → closedByOwner | closedByModeration`과 증가하는 `lifecycleVersion`으로 표현한다. `moderationRoomCleanupJobs/{roomID}` schema v2가 콘텐츠 즉시 정리와 14일 보존 종료 정리를 `content → retention` 두 단계로 수렴시킨다.
- 콘텐츠 정리 뒤 `Rooms/{roomID}`는 공용 `tombstoneSchemaVersion: 1` 문서가 된다. 방 이름·생성자·정렬용 시각·종료 유형/코드/시각과 `expiresAt = closedAt + 14일`만 남기며, 메시지·마지막 메시지·이미지 경로·하위 콘텐츠·Storage는 즉시 제거한다. `expiresAt`은 Firestore TTL이 아니라 scheduler due time이다.
- 아직 `users/{uid}/joinedRooms/{roomID}`가 남은 사용자만 종료 tombstone을 단건 읽을 수 있다. `acknowledgeRoomClosure`가 본인 member/joinedRooms/roomStates와 기존 legacy notice를 멱등 삭제한다. 방장 삭제를 수행한 creator는 즉시 정리하며 안내하지 않는다.
- 기존 Production `users/{uid}/roomClosureNotices/{roomID}` schema v2는 새로 만들지 않고, 기존 30일 TTL과 앱 호환 읽기만 유지해 자연 만료시킨다.
- transaction 밖 cleanup은 deterministic `chatMessageCleanupJobs/{jobID}`와 `moderationRoomCleanupJobs/{roomID}`가 `pending | processing | retryPending | awaitingExpiry | completed | failed`로 수렴시킨다.
- `Rooms/{roomID}/bans/{moderationPrincipalID}`가 room ban source다. client read/write는 금지하고 creator 전용 서버 API로 내보내기·해제한다. ban은 활성 방 list/search/preview/message/media read를 막지 않고 membership 생성·재가입과 참여자 전용 Socket/message/media write만 거부한다.
- ban entry는 자유 입력 없이 canonical 사유, ban 시점 최소 표시 snapshot과 증가하는 stateVersion을 저장한다. ban 목록은 재가입 새 UID의 최신 프로필을 역연결하지 않고 room-scoped opaque token만 반환한다.
- 관리자 방 폐쇄는 `Rooms.lifecycleStatus = closedByModeration`을 먼저 기록해 join/read/write/Socket/push를 차단하고 물리 cleanup은 별도 재시도 상태로 수렴시킨다.
- 수동 creator leave는 기존 방 삭제를 사용한다. 일시 제한·deletionPending은 승계하지 않고, creator 계정 삭제 최종 확정·영구 정지는 durable membership sweep과 방별 transaction으로 oldest eligible active member에게 승계한다.
- 영구 정지 사용자는 모든 room membership·joinedRooms에서 제거하며 해제 뒤 자동 복구하지 않는다. 승계 중 방은 active로 운영하지만 기존 owner capability는 즉시 차단한다. 적격자 없음은 삭제 시 `closedByOwner`, 영구 정지 시 `closedByModeration`으로 기존 종료 lifecycle에 수렴시킨다.

### Membership와 참여중 목록

- authoritative membership: `Rooms/{roomID}/members/{uid}`. 나가면 member 문서를 hard delete한다.
- 참여중 목록 projection: `users/{uid}/joinedRooms/{roomID}`.
- 방 생성은 room 문서, owner member 문서, joinedRooms projection을 하나의 transaction으로 저장한다.
- projection 필드: `roomID`, `role`, `joinedAt`, `lastReadSeq`, `isClosed`, `updatedAt`.
- 마지막 메시지는 `Rooms.lastMessage*`만 source로 사용하며 사용자별 projection으로 fan-out하지 않는다.
- 전체 참여자 목록은 member collection을 stable document ID 순서로 pagination한다.
- 로컬 캐시는 membership replica가 아니라 최근 sender 표시용 bounded cache다.
- `RoomProfileDisplayCache`는 room당 20명 LRU이며 TTL은 두지 않는다.

### Read state

- `ChatRoomReadStateStore`는 앱 실행 중 unread/preview 공유 상태이며 영속 source가 아니다.
- 앱 재실행 시 Firestore `Rooms`와 joinedRooms projection에서 복원한다.
- snapshot은 `latestSeq`, `lastReadSeq`, `lastMessageSenderUID`, `latestMessagePreview`, `latestMessageAt`를 가진다.

### 전역 차단과 로컬 redaction

- `users/{uid}/blockedUsers/{blockedUID}`는 Chat·Lookbook·Profile이 공유하는 전역 차단 source다.
- A가 B를 차단하면 A만 새로 admission되는 B 콘텐츠를 숨긴다. B의 참여자 목록·프로필·공동방은 바꾸지 않고 차단 사실을 알리지 않는다. A가 B에게 직접 상호작용할 때만 A에게 차단 해제를 안내한다.
- Chat은 차단 성공 전에 현재 화면 window에 들어온 메시지를 세션 동안 유지한다. hidden event는 strict seq와 원본 pagination cursor를 소비하지만 별도 redacted marker를 만들거나 기존 본문·첨부·FTS·미디어 cache를 소급 삭제하지 않는다.
- 계정별 마지막 성공 UID snapshot을 메모리 Store의 초기값으로 사용한 뒤 owner-only 서버 relation으로 교체한다. snapshot 없이 서버 조회가 실패하면 UGC 진입을 fail closed한다.
- 차단 해제 뒤 현재 방을 강제 재조회하지 않는다. 이후 메시지는 즉시 admission하고 과거 메시지는 재진입·pagination·일반 동기화에서 자연 복원한다.

### 미디어 격리·정규화·신고 evidence

- `Rooms/{roomID}/MediaUploads/{uploadID}`는 ADR-016의 reservation을 `uploading → queued → processing → ready | canceled | failed | expired` 상태 머신으로 확장한다.
- 별도 processing 문서는 만들지 않는다. `MediaUploads`가 `clientMutationID`, attachment별 단일 quarantine `uploadSources`, attempt, `leaseToken/leaseExpiresAt`, `executionName`, `processingSlotID`, `nextAttemptAt`, retry/failure와 normalized manifest를 함께 소유한다. 업로드 예약과 서버가 발급한 signed target은 24시간, 처리 deadline은 finalize가 source 검증을 마친 뒤부터 6시간이며 terminal 상태에는 최소 멱등 결과만 남겨 7일 뒤 TTL 삭제한다. 앱 outbox에는 signed target 자체를 영속화하지 않는다.
- quarantine은 환경별 `asia-northeast3` Standard 전용 bucket의 `{roomID}/{senderUID}/{uploadID}/{attachmentID}/source`다. soft delete·versioning을 끄고 1일 lifecycle을 비정상 잔존 객체 cleanup 안전망으로 둔다. source는 ready/canceled/final failed/expired 확정 즉시 삭제한다. ready는 일반 media bucket의 `rooms/{roomID}/messages/{messageID}/attachments/{attachmentID}/{display|thumbnail}`, evidence는 별도 bucket의 `{bundleID}/g{attemptGeneration}/{attachmentID}/display`다. evidence copy는 source generation을 고정하고 destination create-if-absent·generation delete와 Firestore generation/lease fence를 결합한다. retention cleanup은 객체 전부를 삭제한 뒤 bundle 문서를 완전 삭제하고 비민감 cleanup receipt만 7일 보존한다.
- processing 완료 전에는 message document와 seq를 만들지 않는다. `processing → ready` transaction에서만 message·room seq·media index·room summary·`chatMediaDeliveryJobs/{roomID_messageID}`를 함께 생성하고 두 processing slot을 반환한다. text Socket transaction과 동일한 `Rooms.seq` 문서를 읽고 쓰므로 경합은 Firestore가 재시도하며 seq 중복·gap을 만들지 않는다.
- 전용 Cloud Run은 실제 MIME·codec·크기·해상도·duration·track을 검증하고 불필요 metadata를 제거한다. 외부 유해성 의미 판정은 수행하지 않는다.
- 이미지는 메시지당 최대 30장, quarantine source 각 15 MiB·합산 150 MiB·긴 변 4096px다. iOS는 정적 이미지의 방향 bake, sRGB, metadata 제거를 적용하고 HEIC/HEIF·JPEG는 JPEG quality 0.92, PNG는 초기 투명/비투명 모두 PNG로 보존한다. GIF animation은 그대로 유지한다. 서버 transport는 JPEG·PNG·animated GIF만 허용하며 raw HEIC/HEIF는 거부한다. 입력은 정적 64M pixel, GIF 200 frame·frame당 16,777,216 pixel·총 100M decoded pixel, 이미지당 60초로 제한한다. 동영상은 iOS가 720p H.264/AAC MP4 source를 준비하고 메시지당 1개·350 MiB·길이 제한 없음·remux 10분 timeout을 적용한다. 이미지와 영상 모두 attachment당 하나의 V4 signed PUT으로 quarantine source에 전송하고 서버가 SHA-256·크기·MIME를 검증한다. 서버가 `min(1초, duration/2)`에서 512px JPEG thumbnail을 생성하며 실패는 `invalidMedia`다. 이미지는 private Cloud Run Service(min 0, concurrency 1), 영상은 Cloud Run Job에서 각각 2 vCPU·1 GiB로 처리한다.
- `moderationMessageIncidents/{incidentID}`는 review revision별 긴급/전체 고유 신고 principal 수, `queueClass`, review/visibility/evidence 상태를 서버 전용으로 집계한다. 일반 단일 신고는 `holding`, 같은 메시지 고유 신고자 2명은 `reviewRequired`, 긴급 단일 신고는 `urgent`다. `holding && reviewDueAt <= serverNow`는 scheduler로 상태를 바꾸지 않고 관리자 직접 조회에 포함한다.
- 같은 작성자의 최근 7일 `reportedMessages` 3개와 `messageReporters` 2개가 함께 조회될 때만 사용자 단위 검토 신호로 사용한다. 두 marker query를 분리해 두 번째 신고자가 네 번째 이전 메시지에만 있어도 놓치지 않으며 각 read는 3개와 2개로 제한한다. 충족 시 `messagePatternReviewUntil = min(세 번째 최신 메시지 시각, 두 번째 최신 신고자 시각) + 7일`을 기록하고 관리자 API가 server now와 비교하므로 만료 scheduler가 필요 없다. 긴급 2명 또는 전체 3명의 24시간 threshold와 관리자 수동 조치만 전역 `hiddenPendingReview`를 만든다.
- message incident/revision/reporter/submission/bundle/guard/job ID는 domain/version을 포함한 canonical tuple SHA-256으로 계산하고 최초 review revision은 0이다. `moderationMessageEvidence/{bundleID}`는 incidentID + reviewRevision의 결정적 ID로 제한된 텍스트 snapshot과 해당 메시지에서 표시된 모든 정규화 `display` attachment를 함께 소유한다. 이미지 묶음은 전체 이미지, 동영상은 전체 정규화 MP4 1개를 보존한다.
- `moderationMessageGuards/{incidentID}`는 클라이언트가 읽을 수 없는 신고/삭제 경합 원장이다. 삭제 transaction이 먼저 commit되면 `messageAlreadyDeleted`를 반환하고 신고·evidence·moderation count는 만들지 않는다. 단, 이전에 보지 못한 `clientRequestID`이면 최상위 transport receipt와 해당 1분 limiter slot은 생성한다. 신고 preparation transaction이 먼저 commit되면 evidence copy를 예약하고, 뒤이은 삭제는 UI tombstone을 즉시 만들되 ready media cleanup을 copy 완료 또는 terminal failure까지 기다린다. copy 완료 뒤에만 accepted 신고를 확정하고 terminal failure면 신고 집계 없이 hold를 해제한다.
- 별도 관리자 작업 목록 projection은 두지 않는다. 관리자 API는 `moderationMessageIncidents`, `moderationUserReports`, `moderationRoomReports`를 직접 필터·정렬한다. Evidence 원본은 클라이언트에 공개되지 않으며 활성 플랫폼 관리자가 서버 인증을 거쳐 특정 객체만 제한적으로 조회한다.
- `chatMediaProcessingSlots/{slotID}`은 전역 server-only 고정 execution lease다. Development는 image 1/video 1, Production 초기값은 image 4/video 1이며 dispatcher가 slot을 얻은 경우에만 Job execution을 시작한다. 별도 principal upload slot은 canonical principal마다 image 2/video 1을 transaction 점유하며 `uploading|queued|processing` 동안만 유지한다. terminal 즉시 반환하므로 이는 누적 전송량이나 최대 60장 총량 제한이 아니라 순차 backpressure다. 24시간 byte hard cap은 초기값을 두지 않는다.
- Phase 7.1 worker 성공은 같은 processing lease에 `technicalValidationResult`, `normalizedManifest`, `metadataRemovalVersion`, `workerCompletedAt`을 기록한다. 이 시점의 ready bucket 객체는 staging 상태라 클라이언트에 공개되지 않으며, Phase 7.2의 lease 재검증·message/seq transaction이 `ready`를 확정한 뒤에만 공개·source cleanup·slot 반환이 일어난다. 확정 message attachment와 `mediaIndex`는 worker가 검증한 display content type과 `frameCount`·`animated`를 근거로 `mediaFormat: jpeg|png|gif|mp4`와 `animated: Bool`을 저장한다. GIF UI는 `mediaFormat == gif && animated == true`일 때만 확정 표시한다.
- v2 message는 `mediaContractVersion: 2`, server-only `mediaUploadPath`, `readyAttachmentIDs`를 가진다. 일반 media Storage Rules는 공개 message가 존재하고 visible·미삭제이며 요청 attachment가 `readyAttachmentIDs`에 포함된 경우만 `display/thumbnail` get을 허용한다. `ready` source cleanup은 즉시 시도하고 15분 scheduler가 `pending|failed`를 재시도한다. canceled/failed/expired의 normalized ready 객체는 고아 객체로 함께 삭제한다.
- v2 attachment와 `mediaIndex`는 `bucketOriginal/pathOriginal`, `bucketThumb/pathThumb`을 함께 저장한다. Phase 7 정규화 결과는 환경별 일반 media bucket을 명시하고, 출시 이력 없는 v2 계약에서 bucket 추론을 하지 않는다. 기존 v1 attachment cleanup에만 기본 Firebase Storage bucket fallback을 유지한다.
- 메시지/방 cleanup job schema v2는 `storageTargets: [{bucket, prefix}]`로 실제 bucket과 prefix를 보존한다. schema v1의 `storagePrefixes`는 기본 bucket 대상으로만 해석해 기존 cleanup과 호환한다.
- `chatMediaDeliveryJobs`는 Socket watcher가 60초 lease로 claim한다. 기존 `receiveImages/receiveVideo`와 FCM fan-out이 끝나면 `completed`, 실패하면 지수 backoff `retryPending`으로 돌아간다. 전달은 at-least-once이며 messageID/seq가 수신측 first-wins dedupe key다. job은 7일 TTL이다.
- 로컬 `chatOutgoingOutbox`는 `uploadID`, `clientMutationID`, `processingStatus`, `statusCheckedAt`, `terminalAt`, `expiresAt`, `sessionPayloadJSON`을 저장한다. session payload는 재조회에 필요한 upload identity·종류·만료 시각만 포함하고 signed PUT URL·필수 header는 저장하거나 로그에 남기지 않는다. 보호된 local source 경로는 별도 outbox payload에 유지한다. 전송 중 네트워크 단절·방 이탈·앱 종료는 로컬 실패로 처리하고 source는 Application Support의 전용 outbox 경로에 backup 제외·`completeUntilFirstUserAuthentication`으로 보존해 재시도/삭제를 제공한다.

## 계정 삭제 계약

- `users/{uid}`는 `accountStatus: active | deletionPending`과 서버 발급 `accountGenerationID`를 가진다.
- `accountDeletionIntents/{intentID}`는 UID/generation/provider/auth session/nonce hash/5분 `expiresAt`을 가진 서버 전용 일회성 문서다.
- `accountDeletionRequests/{requestID}`는 `grace | finalizing | retryPending | completed | cancelled`, stage, lease, retry, `cancelableUntil`, receipt hash를 가진다.
- request ID는 UID와 generation으로 만든 비식별 결정적 hash이며, 새 generation의 재가입 계정과 과거 worker를 분리한다.
- 완료/cancelled request와 notification outbox는 `expiresAt` 기준 30일, 비식별 `accountDeletionAuditLogs`는 90일 TTL 대상이다.
- `completedDeletionSuppressions`는 백업 복구 시 의도적 삭제를 되살리지 않기 위한 HMAC 원장이다.
- 모든 deletion collection은 클라이언트 read/write를 거부한다. 상태 조회는 App Check를 강제하는 opaque receipt callable만 사용한다.
- pending 사용자의 공개 프로필/프로필 이미지 read, 모든 쓰기·관리자 권한·Socket 연결을 차단한다.

### 룩북 공유 메시지

- 메시지 경로: `Rooms/{roomID}/Messages/{messageID}`.
- 공유 메시지는 `messageType = lookbookShare`, `sharedContent` snapshot, 빈 attachments를 사용한다.
- `sharedContent`는 `schemaVersion`, `contentType`, 필수 brand/season/post ID와 제목·부제·thumbnail snapshot을 가진다.
- 카드 최초 렌더링은 snapshot을 사용하고 탭 후 원본 상세를 최신 조회한다.
- 기존 `messageType == nil` 메시지는 attachments 유무로 text/media 호환 decode한다.
- 선택 이유: ADR-011, ADR-012, ADR-013.

## 스타일 무드 계약

- canonical 문서: `styleMoods/{moodID}`. `moodID`는 변경하지 않는 lower snake_case ID이며 동적 관리자 생성은 Firestore 자동 ID를 사용할 수 있다.
- 공개 필드: `schemaVersion`, `displayName`, `normalizedName`, `displayGroup`, `aliases`, `sortOrder`, `isFeaturedInOnboarding`, `status`, `createdAt`, `updatedAt`.
- `displayGroup`은 선택 UI 분류이며 taxonomy 자체는 flat하다.
- 일반 인증 사용자는 `status == active` 문서만 읽고, 실제 `brandAdmins/{uid}.isActive == true`인 총 관리자는 inactive도 읽는다. 모든 클라이언트 직접 쓰기는 금지한다.
- 이름/alias 충돌 방지: 서버 전용 `styleMoodTermIndex/{sha256(normalizedTerm)}`. `moodID`, `termType`, `createdAt`을 가진다.
- `displayGroup` canonical 값은 `베이직·포멀`, `스트릿·트렌드`, `헤리티지·유틸리티`, `스포츠·아웃도어`, `빈티지·서브컬처`, `로맨틱·익스프레시브`이며 iOS도 같은 raw value를 사용한다.
- `brands/{brandID}.moodIDs`와 `brands/{brandID}/seasons/{seasonID}.moodIDs`는 각각 별도의 0...5개 고유 active mood ID 집합이며 순서·대표 무드 의미가 없다.
- 관심 스타일 브랜드 조회는 사용자 `selectedMoodIDs` 최대 5개를 `brands.moodIDs array-contains-any`에 전달하고 `likeCount DESC`, 문서 ID ASC로 정렬한다.
- 관심 스타일 pagination cursor는 정렬 필드 값 `(likeCount, brandID)`을 사용한다. `deletionStatus` 누락 legacy 브랜드 호환을 위해 query 조건에는 포함하지 않고 Domain 가시성 정책으로 필터링한다.
- 브랜드·시즌 `moodIDs` patch는 총 관리자 callable만 수행한다. `updateBrand`는 일반 필드와 선택적 무드 patch 권한을 분리하고, `updateSeasonMoods`는 기존 시즌의 무드만 교체한다. 자동 import 시즌은 `moodIDs: []`로 생성하고 시즌 문서 client create/update는 허용하지 않는다.
- seed 상태: 서버 전용 `styleMoodSeedMetadata/current`. `version`, `contentHash`, `count`, `appliedAt`을 가진다.
- 초기 v1은 56개, 온보딩 기본 노출은 20개다. 원본은 `functions/seeds/style-moods.v1.json`이다.
- 관리 write는 총 관리자 callable `createStyleMood`, `updateStyleMood`만 사용한다. 사용 중인 무드는 hard delete하지 않고 `inactive`로 전환한다.
- seed는 `npm run seed:style-moods -- --project {projectID}`가 dry-run이며 `--apply`를 명시해야만 transaction으로 반영한다.
- 상세 결정: ADR-022와 현재 task의 `seed-spec.md`, `data-api-contract.md`.

## Lookbook 핵심 계약

### 기본 계층과 권한

- 계층: `brands/{brandID}/seasons/{seasonID}/posts/{postID}`.
- 총 관리자: `brandAdmins/{uid}.isActive == true`.
- 브랜드 owner/admin: `brands/{brandID}/admins/{uid}.role in [owner, admin]`.
- `brands.ownerUIDs/adminUIDs`와 과거 capability 필드는 신규 권한 source로 사용하지 않는다.
- 브랜드명 중복 방지는 `brandNameIndex/{normalizedName}` 계열 transaction으로 처리한다.
- Lookbook read DTO는 경로 ID를 포함하지 않고 Repository가 `DocumentSnapshot.documentID`를 mapper에 전달한다.
- 시즌 생성은 import worker의 Admin SDK materialization만 사용하며 문서 identity는 Firestore 경로 ID를 canonical source로 유지한다. 앱 client direct create/update는 허용하지 않는다.

### 사용자 상태

- 브랜드/시즌/포스트/댓글 상호작용은 `users/{uid}` 하위 state projection과 각 interaction store를 사용한다.
- 정확한 collection path와 DTO는 관련 Repository 및 `firestore.rules`를 함께 확인한다.

### 브랜드 요청

- 클라이언트는 요청 collection을 직접 읽고 쓰지 않고 callable Functions를 사용한다.
- 사용자 상태: `submitted`, `reviewing`, `added`, `rejected`.
- 운영 상태: `requested`, `processing`, `completed`, `rejected`.
- 브랜드 요청 `rejected/completed`는 최근 14일과 이전 이력을 지원한다.
- 삭제 요청 목록에는 이 14일 계약을 적용하지 않는다.

### 시즌 import extraction metadata

- `importJobs.imageCandidates`는 materialization에 쓰는 기존 `{sourceURL, alt}` 배열 계약을 유지한다.
- `imageCandidateEvidence`는 candidate fingerprint, parser strategy, static/rendered source kind와 query value를 제거한 source origin/path/query key를 가진다.
- `imageExtractorVersion`, `platformAdapterKey/version`, `domainAdapterKey/version`은 extraction run의 재현 경계다. Phase 7 extractor는 `1.2.3`, Cafe24 platform adapter는 `cafe24@1.0.1`이다. Generic 결과와 현재 미등록 상태인 domain adapter 값은 `null`이다.
- extraction cache는 candidate/hash/quality뿐 아니라 extractor와 platform/domain adapter key/version 전체가 현재 registry와 일치할 때만 재사용한다.
- discovery diagnostic은 같은 의미의 `candidateEvidence`, `extractionVersions`를 반환한다.
- 일반 시즌 discovery의 source of truth는 `brands/{brandID}/seasonDiscoveryJobs/{jobID}`다. 후보는 job 하위 `candidates`, 관리자 동일성 결정은 `reviews`에 저장한다. 브랜드 문서의 active/published job·generation·snapshot hash는 빠른 진입용 projection이다.
- Phase 7 candidate는 기존 `coverImageURL`과 함께 `coverImageSource: list | detail | none`, `coverImageStrategy`를 저장한다. job에는 `coverImageCount`, `listCoverImageCount`, `detailCoverAttemptCount/SuccessCount/FailureCount/SkippedCount`를 관찰용으로 저장한다. 이 값은 discovery status와 issue fingerprint를 결정하지 않으며 candidate snapshot hash에는 포함된다. 로컬 contract 3 구현은 완료했고 배포 runtime은 별도 승인 전 contract 2를 유지한다.
- 브랜드 projection의 `discoveryStatus`는 구형 경로의 `idle/queued/running/success/failed`와 durable 경로의 `succeeded/awaitingReview/correctionRequired/cancelled/superseded`를 모두 읽을 수 있어야 한다. 세부 작업 상태와 action 판단의 source of truth는 job 문서다.
- discovery job은 현재 비교 가능한 단조 증가 정수 `extractionContractRevision`을 가진다. 후속 `lookbook-extraction-issue-operations` 구현에서는 Functions compile-time 상수를 extractor readiness 기준에서 제외하고 server-only runtime registry와 Worker runtime contract를 source of truth로 사용한다.
- Phase 4A의 버튼 기반 `improvementRequested*` UI/API 읽기·쓰기는 제거했다. 기존 개발 데이터의 필드는 파괴적으로 일괄 삭제하지 않는다. 시즌 discovery와 이미지 import는 로직 불충분 판정 시 공통 redacted 40자 fingerprint cluster를 자동 기록한다.
- 이미지 import 요청은 `discoveryJobID`, `generation`, `candidateSnapshotHash`, `candidateIDs`를 함께 검증하며 `newSeason` 후보 seed를 기존 `importJobs`에 복사한다.
- `expiresAt`은 job/candidate/review collection group 각각에 TTL을 설정한다. active 및 `awaitingReview`/`correctionRequired`에는 값을 두지 않고, 일반 terminal/candidate는 30일, 실패 요약/review audit은 60일이다.
- candidate/source fingerprint에는 원본 query value를 저장하지 않는다.
- Phase 2 import job은 `expectedCountEvidence`, `programmaticGalleryEvidence`, `extractionQualityStatus/reasons`, static/rendered/source/content-hash candidate count와 hash 완료·실패 수를 기록한다.
- `imageCandidates`는 content hash가 확인된 동일 bytes 후보를 first-wins로 제거한 materialization 입력이다. hash 조회 실패 후보는 자동 제거하지 않는다.
- Phase 4 import job은 `dispatchGeneration`, `reviewGeneration`, `reviewSnapshotHash`, `reviewStatus`, `resumeFrom`, `templateSignature`, `trustBaselineID/trustBaselineMatched`, `reviewCandidateKeys/approvedCandidateKeys`를 가진다.
- `status=awaitingReview`, `phase=reviewing`이면 season/post materialization 전 관리자 판단을 기다린다. 승인 후 같은 job이 `resumeFrom=materializing`으로 재개되며 task identity는 `dispatchGeneration`을 포함한다.
- `brands/{brandID}/importJobs/{jobID}/reviews/{reviewGeneration}`은 snapshot hash, decision, 승인/제외 후보, expected count, reviewer와 extraction version을 보존하는 server-only audit다.
- `lookbookExtractionTrustBaselines/{trustBaselineID}`은 `brandID + host + templateSignature + extractor major + adapter versions` scope의 자동 승인 baseline이다. 안전한 정상 승인만 생성하며 클라이언트 직접 read/write 대상이 아니다.
- `lookbookExtractionEvidence/{evidenceID}`은 `brandID`, `jobPath`, `generation`, `status/stage`, `issueFingerprint`, `storagePath`, `expiresAt`을 가진 server-only occurrence ledger이며 7일 뒤 정리한다.
- Storage `lookbook-extraction-evidence/{evidenceID}.json`은 failed/needsReview run의 allowlist DOM 구조, redacted source, 후보/expected evidence와 extraction version만 가진다. 전체 HTML/script/screenshot과 query value는 저장하지 않는다.
- `lookbookExtractionIssueClusters/{fingerprint}`은 `stage + platform + parserStrategy + failureReasons + qualityReasons + templateSignature + extractorMajorVersion` fingerprint를 document ID로 사용한다.
- canonical stage는 `seasonDiscovery | seasonImageImport`다. blocked/fixed runtime은 각각 `contract:{revision} | extractor:{semver}` 형식이며 stage와 다른 종류 또는 잘못된 형식은 비교하지 않는다.
- cluster는 `occurrenceCount/recurrenceCount`, `adapterScope/adapterKey`, `firstSeenAt/lastSeenAt`, `stateVersion/status`, fixed/verified runtime과 대표 evidence projection을 가진다. 영향 domain/brand 표본과 부정확한 count는 저장하지 않고 정확한 job은 occurrence ledger로 조회한다. 같은 evidence ledger ID 또는 같은 job generation occurrence는 횟수를 다시 증가시키지 않는다.
- 논리 상태는 `open/inProgress/needsGroundTruth/fixed/verified/wontFix`다. `fixed`는 Production live revision과 smoke 검증, `verified`는 해당 revision의 실제 재시도 성공을 의미한다. 재발하면 `open`으로 돌아간다.
- `lookbook-extraction-cluster-evidence/{fingerprint}/{evidenceID}.json` 중 cluster가 가리키는 대표 redacted evidence 한 개는 미해결 동안 보존한다. 교체는 정보 점수 tuple로 결정하고 성공 뒤 이전 object를 정리한다. `verified/wontFix` 뒤 60일에 cluster와 함께 삭제하며 occurrence evidence 7일, terminal job 60일과 서로 다른 정책이다.
- job에는 `extractionIssueFingerprint/status`, 선택적 `extractionIssueWontFixReason`, blocked runtime과 retry available runtime/시각만 projection한다. server-only `lookbookExtractionRuntime/current`와 Worker `/runtime-contract`를 검증한 release verifier만 `fixed`와 retry readiness를 기록한다.
- `lookbookExtractionIssueAuditLogs/{requestID}`은 mutation caller/action/fingerprint, before/after status와 stateVersion, request hash, `createdAt/expiresAt`을 가진 server-only 멱등 audit다. `expiresAt` TTL은 60일이다.
- Phase 3 read API는 cluster allowlist와 대표 redacted evidence만 반환하고 최근 브랜드/job 사례와 `brandID` filter를 제공하지 않는다. 정확한 영향 job은 job의 `extractionIssueFingerprint` collection-group projection으로만 조회한다.
- `lookbookExtractionFixVerificationRuns/{runID}`은 target fingerprint/stage, source job path hash, candidate count/key, failure/quality reason, Worker/runtime/source revision과 상태를 가진 통과 영수증이며 24시간 TTL이다. URL·HTML·token은 저장하지 않는다.
- `lookbookExtractionFixReleases/{releaseID}`은 fixed runtime별 projection cursor/count/status를 가져 최대 200개 job씩 멱등 재개하고 60일 TTL을 가진다.
- `lookbookExtractionRuntime/current`는 Production 100% traffic과 runtime/smoke를 통과한 Worker/service/source revision, discovery contract, image extractor, adapter map과 verification run을 기록한다.
- 상세 field/API/cleanup 계약은 `docs/ai/tasks/lookbook-extraction-issue-operations/design.md`를 따른다. 현재 1인 운영에는 assignee, Jira ticket, SLA 필드를 두지 않는다.
- Phase 6 import job은 `repairStatus`, `repairGeneration`, `repairTargetSeasonID`, `repairSnapshotHash`와 keep/add/reorder/remove count를 가진다. `repairStatus=noChanges`는 add/reorder/removeCandidates가 모두 0이라 시즌 write와 관리자 적용이 필요 없는 terminal 비교 결과다.
- `brands/{brandID}/importJobs/{jobID}/repairs/{repairGeneration}`은 keep/add/reorder/removeCandidates, `orderedPostIDs/allPostIDs`, `resultingPostCount`, `repairSnapshotHash`, 적용 audit를 가진 server-only preview다. 변경 없음도 audit status `noChanges`로 남긴다.
- repair 적용은 기존 post의 `orderIndex/sourceSortIndex`만 보정하고 새 post에만 deterministic ID와 새 `createdAt`을 부여한다. remove-candidate post는 삭제하지 않고 후보 뒤 순서로 보존한다.

## 룩북 삭제 계약

### Lifecycle

- 브랜드/시즌/포스트 hard delete callable은 제공하지 않는다.
- 복구 가능 기간은 7일이며 `restoreUntil == purgeAfter`다.
- 앱 삭제 요청 목록은 `active/failed`만 표시한다.
- `purged/cancelled/restored` projection과 감사 로그는 서버 운영 이력으로 유지한다.
- 일반 사용자는 삭제된 target과 관리자 사유를 볼 수 없다.
- 브랜드 삭제 요청/취소는 총 관리자만, 시즌·포스트 삭제/복구는 총 관리자 또는 해당 브랜드 owner/admin만 가능하다.

### `lookbookDeletionRequests/{requestID}`

필드 그룹만 이 문서에 유지한다. 실제 read/write는 `functions/src/index.ts`를 확인한다.

| 그룹 | 주요 필드 |
| --- | --- |
| 식별 | `requestID`, `targetType`, `targetID`, `targetPath`, `brandID`, `seasonID`, `postID` |
| 상태 | `status`, `requestedBy/At`, `restoreUntil`, `purgeAfter`, `reason`, `updatedBy/At` |
| 자동 재시도 | `purgeAttemptCount`, `lastPurgeAttemptAt`, `retryAfter`, `autoRetryEligible`, `purgeErrorMessage` |
| manual retry | `manualRetryState`, `manualRetryToken`, `manualRetryCount`, `manualRetryRequestedAt/By` |
| 실행 lease | `purgeLeaseToken`, `purgeLeaseUntil`, `purgeExecutionSource`, `lastPurgeClaimedAt` |
| 완료 | `purgedAt`, `purgedBy`, 취소/복구 actor와 timestamp |
| 표시 snapshot | `targetDisplayName`, `targetImagePath`, 브랜드·시즌·포스트 이름/thumbnail snapshot |

- 목록 callable은 snapshot이 없는 기존 projection의 응답 summary만 원본에서 보강하며 backfill write하지 않는다.
- 표시 제목은 target별 snapshot을 우선하고 ID/UID를 사용자 제목 fallback으로 사용하지 않는다.

### 감사와 lease

- 감사: `lookbookDeletionAuditLogs/{logID}`. action, request/target 식별자, actor, reason, before/after 상태, `createdAt`을 기록한다.
- lease: `lookbookDeletionPurgeLeases/{brandID}`. `leaseToken`, `leaseUntil`, `requestID`, `brandID`, `source`, `claimedAt`을 기록한다.
- request와 lease token이 모두 실행 token과 일치할 때만 finalize한다.
- 두 collection 모두 일반 클라이언트 직접 접근을 허용하지 않는다.

### Scheduled purge

- `Asia/Seoul` 매일 04:00 실행한다.
- page size는 active/failed 각각 20개이며 전체 실행 상한이 아니다.
- `brand -> season -> post` pass, 같은 브랜드 순차, 서로 다른 브랜드 최대 3개 병렬이다.
- active query: `status + targetType + purgeAfter + requestID`.
- failed query: `status + autoRetryEligible + targetType + purgeAfter + retryAfter + requestID`.
- 7분 이후 신규 claim을 중단하고 시작한 작업은 완료를 기다린다.
- 실패는 최대 3회 자동 재시도 후 `autoRetryEligible = false`로 전환한다.
- 부모 purge 성공 시 같은 범위 하위 active/failed projection도 `purged`로 닫는다.
- Storage는 검증된 `brands/{brandID}/` 하위 raw path만 삭제하고 외부 URL은 삭제하지 않는다.
- 상세 결정과 재검토 조건: ADR-018.

## Firebase와 로컬 저장소

- Functions export와 callable/trigger: `functions/src/index.ts`.
- Firestore rules/index: `firestore.rules`, `firestore.indexes.json`.
- Storage rules: `storage.rules`.
- GRDB schema/migration: `docs/ai/entrypoints/DATA.md`가 안내하는 `AppDatabase`, migration registry, Store와 persistence record/mapper.
- 운영 배포 결과는 task `progress.md`에 기록하고 이 문서에는 revision/일회성 QA 로그를 복사하지 않는다.

## 변경 체크리스트

- Domain entity와 DTO/mapper를 분리했는가?
- Repository/UseCase 경계가 필요한가?
- 기존 문서 decode 호환 또는 migration이 필요한가?
- Firestore rules/index와 Storage rules가 바뀌는가?
- callable/trigger와 iOS wrapper 계약이 일치하는가?
- 운영 데이터 삭제·마이그레이션·배포 승인을 받았는가?
- 장기 결정이면 ADR, 작업 상태면 task `progress.md`, 코드 위치면 entrypoint를 갱신했는가?
