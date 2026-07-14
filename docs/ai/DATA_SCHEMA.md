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
| 인증·사용자 | Firebase Auth UID, `users/{uid}` | `AuthenticatedUser.swift`, `UserProfile.swift`, [DATA](entrypoints/DATA.md) |
| Chat room/membership | `Rooms/{roomID}`, `Rooms/{roomID}/members/{uid}`, `users/{uid}/joinedRooms/{roomID}` | [CHAT](entrypoints/CHAT.md), ADR 관련 task |
| Chat message/cache | `Rooms/{roomID}/Messages/{messageID}`, GRDB `chatMessage`, `LocalChatUser`, `RoomProfileDisplayCache` | [CHAT](entrypoints/CHAT.md), [DATA](entrypoints/DATA.md) |
| Lookbook | `brands/{brandID}/seasons/{seasonID}/posts/{postID}` | [LOOKBOOK](entrypoints/LOOKBOOK.md) |
| 브랜드 관리 | `brandAdmins/{uid}`, `brands/{brandID}/admins/{uid}` | [LOOKBOOK](entrypoints/LOOKBOOK.md), [FIREBASE](entrypoints/FIREBASE.md) |
| 브랜드 요청 | `brandRequests`, `brandRequestNameIndex`, daily counter/user limit | [FIREBASE](entrypoints/FIREBASE.md) |
| 시즌 import | `seasonCandidates`, `importJobs`, `lookbookExtractionDiagnostics` | [worker architecture](architecture/LOOKBOOK_IMPORT_WORKER.md) |
| 룩북 삭제 | `lookbookDeletionRequests`, `lookbookDeletionAuditLogs`, `lookbookDeletionPurgeLeases` | 아래 계약, [FIREBASE](entrypoints/FIREBASE.md), ADR-018 |

## 인증과 사용자 식별

- canonical user key는 Firebase Auth `uid`다.
- 문서상 `userID == canonicalUserID == Firebase Auth uid`다.
- 프로필 경로는 `users/{uid}`이며 이메일/provider fallback query는 사용하지 않는다.
- `Rooms.creatorUID`, `Messages.senderUID`, member 문서 ID, joinedRooms owner 경로는 같은 UID를 저장한다.
- Chat room 자기 identity는 `Rooms/{roomID}` 경로의 document ID이며 `ChatRoom.id`로 주입한다. 새 room payload에는 자기 `ID`/`id`를 저장하지 않는다.
- 2026-07-14 운영 Rooms의 legacy 자기 `ID` 4건을 cleanup했으며 사후 감사 기준 `Rooms.ID`/`Rooms.id` 보유 문서는 0건이다.
- `Rooms.participantUIDs`, 사용자 문서의 legacy `joinedRooms` 배열, `roomStates`는 신규 source로 사용하지 않는다.
- GRDB `LocalChatUser.userID`, `RoomProfileDisplayCache.userID`, `chatMessage.senderUID`도 같은 UID 의미다.
- 개발 DB에서 재현된 legacy `chatMessage.senderID NOT NULL` schema만 migration으로 현재 schema로 재작성한다.
- 현재 구현은 앱 미배포 clean break를 적용한 fresh 15개 migration이다. legacy no-op 3개와 `createRoomImage`/`roomImage` table/API는 제거했으며 Phase 3 이전 개발 DB는 앱 삭제·재설치로 초기화한다.
- 메시지 저장 중 FTS 오류는 삼키지 않고 message/FTS/media transaction 전체를 rollback한다. 상세 결정은 `docs/ai/tasks/core-infrastructure-modularization/decisions/phase-3-grdb.md`를 따른다.

## Chat 핵심 계약

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

### 룩북 공유 메시지

- 메시지 경로: `Rooms/{roomID}/Messages/{messageID}`.
- 공유 메시지는 `messageType = lookbookShare`, `sharedContent` snapshot, 빈 attachments를 사용한다.
- `sharedContent`는 `schemaVersion`, `contentType`, 필수 brand/season/post ID와 제목·부제·thumbnail snapshot을 가진다.
- 카드 최초 렌더링은 snapshot을 사용하고 탭 후 원본 상세를 최신 조회한다.
- 기존 `messageType == nil` 메시지는 attachments 유무로 text/media 호환 decode한다.
- 선택 이유: ADR-011, ADR-012, ADR-013.

## Lookbook 핵심 계약

### 기본 계층과 권한

- 계층: `brands/{brandID}/seasons/{seasonID}/posts/{postID}`.
- 총 관리자: `brandAdmins/{uid}.isActive == true`.
- 브랜드 owner/admin: `brands/{brandID}/admins/{uid}.role in [owner, admin]`.
- `brands.ownerUIDs/adminUIDs`와 과거 capability 필드는 신규 권한 source로 사용하지 않는다.
- 브랜드명 중복 방지는 `brandNameIndex/{normalizedName}` 계열 transaction으로 처리한다.
- Lookbook read DTO는 경로 ID를 포함하지 않고 Repository가 `DocumentSnapshot.documentID`를 mapper에 전달한다.
- 시즌 생성 write는 `SeasonWriteDTO`를 사용하며 read DTO와 자기 문서 ID를 encode하지 않는다.

### 사용자 상태

- 브랜드/시즌/포스트/댓글 상호작용은 `users/{uid}` 하위 state projection과 각 interaction store를 사용한다.
- 정확한 collection path와 DTO는 관련 Repository 및 `firestore.rules`를 함께 확인한다.

### 브랜드 요청

- 클라이언트는 요청 collection을 직접 읽고 쓰지 않고 callable Functions를 사용한다.
- 사용자 상태: `submitted`, `reviewing`, `added`, `rejected`.
- 운영 상태: `requested`, `processing`, `completed`, `rejected`.
- 브랜드 요청 `rejected/completed`는 최근 14일과 이전 이력을 지원한다.
- 삭제 요청 목록에는 이 14일 계약을 적용하지 않는다.

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
