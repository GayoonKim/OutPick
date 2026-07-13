# OutPick Data Schema

## 목적

OutPick의 주요 데이터 모델, Firestore 문서 구조, 로컬/런타임 상태 구조를 AI 에이전트가 확인하기 위한 문서다.

## 작성 원칙

- 데이터 모델은 기능 요구사항과 완료 기준에서 출발한다.
- Firebase, Firestore, Cloud Functions, 로컬 저장소 접근은 View에서 직접 하지 않는다.
- Repository와 UseCase 경계를 통해 데이터 접근 책임을 분리한다.
- 확정되지 않은 컬렉션, 필드, 인덱스는 확실하지 않음으로 표시한다.

## 데이터 접근 원칙

- Domain entity는 `OutPick/Features/**/Domain` 또는 `Domains` 아래에 둔다.
- Firestore DTO와 mapper는 Feature별 `Models/DTOs`, `Mapper` 계층을 사용한다.
- Repository protocol은 Domain/ViewModel이 의존하는 계약이다.
- Repository implementation은 Firestore, Cloud Functions, 네트워크, 저장소 구현을 숨긴다.
- UseCase는 Repository를 조합해 화면에 필요한 비즈니스 흐름을 만든다.

## 인증/사용자

현재 확인된 주요 타입/파일:

- `AuthenticatedUser`: `OutPick/Features/Login/Domain/AuthenticatedUser.swift`
- `LoginManager`: `OutPick/Features/Login/Application/LoginManager.swift`
- `LoginManager+Bootstrapping`: 로그인 이후 런타임 초기화
- `UserProfile`: `OutPick/Features/Profile/Domain/UserProfile.swift`
- `UserProfileDraft`: `OutPick/Features/Profile/Domain/UserProfileDraft.swift`
- `UserProfileDTO`: `OutPick/Features/Profile/DTO/UserProfileDTO.swift`

식별 key:

- 사용자 식별 핵심 key는 Firebase Auth `uid`를 그대로 쓰는 `canonicalUserID`다.
- 현재 사용자 ID 접근은 `LoginManager.canonicalUserID` 또는 `CurrentUserProviding.canonicalUserID`를 사용한다.
- 사용자 프로필 문서 경로는 `users/{canonicalUserID}`다.
- 프로필 조회는 `users/{canonicalUserID}` 문서 직접 조회만 사용한다. 이메일/provider field 기반 fallback query는 사용하지 않는다.
- 현재 구현 기준으로 `Rooms.creatorUID`, `Messages.senderUID`, `Rooms/{roomID}/members/{uid}` 문서 ID, `users/{uid}/joinedRooms/{roomID}` owner 경로는 같은 canonical user ID를 저장한다.
- `Rooms.participantUIDs`와 `users/{uid}/roomStates/{roomID}`는 legacy cleanup 대상이다.
- `email`은 표시/연락처 성격의 프로필 필드 또는 legacy snapshot일 수 있지만 권한/쿼리/비교 key로 사용하지 않는다.

로컬 Chat 표시 캐시:

- GRDB `LocalChatUser.userID`와 `RoomProfileDisplayCache.userID`는 canonical user ID(Firebase Auth UID)를 저장한다.
- 문서상 `userID == canonicalUserID == Firebase Auth uid`다.
- `chat-legacy-identity-naming`에서 Swift/API뿐 아니라 물리 GRDB table/column도 `userID` 기준으로 정리했다.
- legacy `userProfile`/`roomParticipant` fallback은 제거한다.
- 앱이 아직 TestFlight/App Store 등으로 배포되지 않았으므로 신규 legacy GRDB table compatibility는 만들지 않는다. 단, 개발 DB에서 실제로 재현된 `chatMessage.senderID NOT NULL` 잔존 schema는 현재 `senderUID` schema로 재작성하는 migration을 유지한다.
- `chatMessage` sender 식별 컬럼은 `senderUID`다. legacy `senderID` 컬럼이 남아 있으면 `GRDBManager.rebuildChatMessageSenderUIDSchemaIfNeeded(in:)`가 `senderUID`로 backfill하고 컬럼을 제거한다.
- Firestore membership source는 `Rooms/{roomID}/members/{uid}` 문서 존재 여부다.
- GRDB/local cache는 전체 room membership replica로 사용하지 않는다. 최근 메시지 sender nickname/avatar 표시를 위한 bounded profile cache로 의미를 축소한다.
- GRDB `RoomMember` table/model/migration은 제거했다. local membership replica는 유지하지 않는다.

대형 membership 구현 계약:

- `Rooms.participantUIDs` 배열은 소형/중형 방에는 단순하지만, 2000~3000명 규모 방의 source of truth로는 부적합하므로 새 write/read source로 사용하지 않는다.
- `chat-membership-model-transition`에서 `Rooms/{roomID}/members/{uid}`를 authoritative membership으로 전환했다.
- 사용자가 방을 나가면 `members/{uid}` 문서는 hard delete한다. `status: active/left` soft-delete는 현재 요구사항에는 사용하지 않는다.
- `users/{uid}/joinedRooms/{roomID}`는 참여중 방 목록 read model이다.
- joined room projection 필드는 `roomID`, `role`, `joinedAt`, `lastReadSeq`, `isClosed`, `updatedAt`으로 확정했다.
- `lastMessage`, `lastMessageAt`, `lastMessageSeq`는 joined room projection에 저장하지 않고 `Rooms/{roomID}` 문서만 source로 사용한다.
- 메시지 전송 시 `Rooms/{roomID}.lastMessage*`는 즉시 갱신하고, 사용자별 joined room projection `lastMessage*` fan-out은 하지 않는다.
- 참여중 목록은 joinedRooms 전체 또는 충분한 범위 fetch 후 `Rooms` batch fetch, `Rooms.lastMessageAt DESC` 클라이언트 정렬로 구성한다.
- 전체 참여자 배열, 전체 참여자 프로필, `unreadCount`는 joined room projection에 넣지 않는다.
- `lastReadSeq`는 기존 `users/{uid}/roomStates/{roomID}`에서 joined room projection으로 통합했다. legacy `roomStates`는 cleanup 대상이다.
- 클라이언트는 자기 projection의 `lastReadSeq`만 단조 증가로 갱신할 수 있고, 나머지 membership/list state는 서버가 쓴다.
- 사용자 프로필 문서의 `joinedRooms` 배열은 bootstrap/runtime source로 사용하지 않는다. legacy field는 cleanup 대상이다.
- `ChatRoomSettingViewController` 사용자 목록은 `Rooms/{roomID}/members`를 member documentID 기준 stable order로 page 단위 조회하며, GRDB 전체 member cache를 source로 사용하지 않는다.
- 메시지 sender bounded profile cache는 `LocalChatUser` 전역 캐시 + `RoomProfileDisplayCache(roomID, userID)` 방별 bounded 관계 테이블로 구현한다.
- `RoomProfileDisplayCache`는 방별 최근 메시지 sender 약 20명 같은 제한된 표시 관계를 관리하고, `ChatRoomSettingViewController` 전체 참여자 목록 source로 사용하지 않는다.
- `RoomProfileDisplayCache`는 room당 20명 LRU eviction을 사용하고 time-based TTL은 두지 않는다.
- 방장이 방을 나가면 방 닫기 semantics로 처리한다.
- 방장 close cleanup은 `participantUIDs` 배열이 아니라 `Rooms/{roomID}/members` 또는 `users/{uid}/joinedRooms` projection 기반으로 Firestore room 하위 문서와 Storage `rooms/{roomID}/` prefix를 정리한다.
- 방장 close cleanup은 별도 cleanup job 문서를 만들지 않고 즉시 성공/실패 응답으로 처리한다. 실패 시 클라이언트는 방 나가기 실패 피드백을 즉시 표시하고, 재시도는 idempotent delete 흐름으로 처리한다.
- 방장 전용 action의 최종 권한은 `Rooms.creatorUID` 기준이다. member doc `role`은 UI/projection 편의 snapshot으로 사용한다.
- Socket Cloud Run, Firestore rules, Functions 운영 배포는 2026-07-03 완료했다.
- `firestore:indexes` 운영 배포와 legacy participant index 삭제는 2026-07-03 완료했다.
- 운영 legacy field count는 0으로 확인했으므로 별도 legacy field cleanup 삭제 작업은 현재 필요하지 않다.

런타임 read state/list summary:

- `ChatRoomReadStateStore`는 앱 프로세스 안에서 unread 계산과 최신 메시지 summary를 공유하는 런타임 store다.
- 저장/권한 source of truth는 아니다. 앱 재실행 후 authoritative state는 Firestore `Rooms`와 `users/{uid}/joinedRooms` projection fetch로 복원한다.
- snapshot은 `latestSeq`, `lastReadSeq`, `lastMessageSenderUID`, `latestMessagePreview`, `latestMessageAt`를 담는다.
- 채팅방 안 수신은 `ChatViewController`/`ChatRoomViewModel` 경로로 반영하고, 채팅방 밖 수신은 `BannerManager`가 `seedIncomingMessage(_:)`와 room preview cache 갱신을 수행한다.

## Chat 데이터

현재 확인된 주요 Domain model:

- `ChatRoom`
- `ChatMessage`
- `JoinedRoomsStore`
- `ChatInitialLoadModels`
- `ChatRoomMediaIndexEntry`
- `ChatRoomSettingMediaItem`
- `ChatMessageSearchIndex`
- `PreparedImage`
- `PreparedVideo`

주요 책임:

- 채팅방 목록, 참여방, 메시지, 미디어, 참여자, 검색 인덱스 상태를 다룬다.
- Repositories와 Managers가 혼재하므로 변경 전 protocol/manager/usecase 흐름을 함께 확인한다.

확실하지 않음:

- Socket/Firestore/로컬 캐시 간 정확한 데이터 소유권은 기능 수정 시 관련 Manager와 Repository를 다시 확인해야 한다.

### Chat 룩북 공유 메시지

목표:

- 채팅방은 빠르게 렌더링하고, 룩북 원본 최신성은 카드 탭 후 상세 화면에서 확인한다.

Domain 후보:

```swift
enum ChatMessageType: String, Codable {
    case text
    case lookbookShare
}

struct LookbookSharedContent: Codable, Hashable {
    enum ContentType: String, Codable {
        case brand
        case season
        case post
    }

    let schemaVersion: Int
    let contentType: ContentType
    let brandID: String
    let seasonID: String?
    let postID: String?
    let titleSnapshot: String
    let subtitleSnapshot: String?
    let thumbnailPathSnapshot: String?
}
```

ID 규칙:

- 브랜드 공유: `brandID` required, `seasonID/postID` nil.
- 시즌 공유: `brandID`, `seasonID` required, `postID` nil.
- 포스트 공유: `brandID`, `seasonID`, `postID` required.

Snapshot 규칙:

- 브랜드: `titleSnapshot = 브랜드명`, `subtitleSnapshot = nil 또는 브랜드`, 대표 이미지.
- 시즌: `titleSnapshot = 시즌명`, `subtitleSnapshot = 브랜드명`, 시즌 대표 이미지.
- 포스트: 포스트에는 별도 title이 없으므로 `titleSnapshot = 포스트`, `subtitleSnapshot = 브랜드명 · 시즌명`, 포스트 대표 이미지.

Firestore 메시지 문서:

- 경로: `Rooms/{roomID}/Messages/{messageID}`
- 기존 메시지 필드 유지.
- 공유 메시지는 `messageType = "lookbookShare"`, `sharedContent` map, `attachments = []`.
- 클라이언트 전송 payload의 `msg`는 선택적 사용자 입력 텍스트다. 함께 보낼 텍스트가 없으면 nil 또는 빈 문자열을 허용한다.
- 서버 저장 문서의 `msg`는 항상 문자열로 채운다.
  - 사용자 입력 텍스트가 있으면 trim한 사용자 텍스트.
  - 사용자 입력 텍스트가 없으면 `sharedContent.contentType` 기반 fallback preview.
  - 브랜드: `브랜드를 공유했어요`
  - 시즌: `시즌을 공유했어요`
  - 포스트: `포스트를 공유했어요`
- 브랜드명, 시즌명, 썸네일은 `sharedContent` snapshot에만 저장하고 공유 카드 렌더링에서 사용한다.
- 서버/클라이언트는 과거 generic preview가 `msg`에 저장된 메시지도 정상 표시해야 한다.

GRDB 로컬 캐시:

- `chatMessage.messageType` TEXT 컬럼 추가 후보.
- `chatMessage.sharedContent` TEXT 컬럼 추가 후보. JSON string으로 저장한다.
- 정렬은 기존 `seq`, `sentAt` 중심으로 유지한다.
- 검색은 공유와 함께 보낸 사용자 텍스트가 있으면 `msg` 기준으로 동작한다. 브랜드명/시즌명 검색 확장은 MVP 이후 별도 결정한다.
- `Rooms.lastMessage`, push preview, 답장 preview 등 compact preview surface는 서버가 저장한 `msg`를 우선 사용한다. legacy/로컬 실패 메시지처럼 `msg`가 비어 있으면 클라이언트가 fallback preview를 계산한다.

호환성:

- 기존 메시지는 `messageType == nil`이어도 정상 decode되어야 한다.
- `messageType == nil && attachments.isEmpty`는 text로 취급한다.
- `messageType == nil && attachments`가 있으면 media 메시지로 취급한다.
- `messageType == lookbookShare`인데 `sharedContent`가 없거나 invalid이면 unavailable 카드 또는 일반 preview fallback으로 처리한다.

서버 검증:

- `chat:lookbookShare` 수신 시 `Rooms/{roomID}`를 조회한다.
- `isClosed == false`, `participantIDs`에 sender 포함, socket room join 상태를 확인한다.
- `contentType`, 필수 ID, 문자열 길이, payload size, rate limit을 검증한다.
- 브랜드/시즌/포스트 원본 존재 여부는 검증하지 않는다. 상세 조회 책임으로 둔다.

## Lookbook 데이터

현재 확인된 주요 Domain entity:

- Brand: `Brand.swift`
- Season: `Season.swift`
- Post: `LookbookPost.swift`
- Comment: `Comment.swift`
- Tag/TagAlias/TagConcept: `Tag.swift`, `TagAlias.swift`, `TagConcept.swift`
- Replacement: `ReplacementItem.swift`
- Brand user state: `BrandUserState.swift`
- Season user state: `SeasonUserState.swift`
- Post user state: `PostUserState.swift`
- Comment user state: `CommentUserState.swift`
- Engagement result: `BrandEngagementResult`, `SeasonEngagementResult`, `PostEngagementResult`, `CommentEngagementResult`
- Season import: `SeasonImportJob`, `SeasonCandidate`, `SeasonImportRequestReceipt`, `SeasonImportBatchProcessResult`, `SeasonImportExtractionProgress`, `SeasonAssetRetryReceipt`

현재 확인된 주요 DTO:

- `BrandDTO`
- `SeasonDTO`
- `PostDTO`
- `CommentDTO`
- `BrandUserStateDTO`
- `SeasonUserStateDTO`
- `PostUserStateDTO`
- `CommentUserStateDTO`
- `TagDTO`
- `TagAliasDTO`
- `TagConceptDTO`
- `ReplacementDTO`
- `SeasonImportJobDTO`
- `SeasonCandidateDTO`

추정되는 Firestore 큰 축:

- `brands`
- `brandNameIndex/{normalizedName}`
- `brands/{brandID}/admins`
- `brands/{brandID}/seasons`
- `brands/{brandID}/seasons/{seasonID}/posts`
- `brandRequests`
- `brandRequestNameIndex`
- `brandRequestDailyCounters/{uid}/brandRequestDays/{yyyyMMdd}`
- `brandRequestUserLimits`
- `lookbookDeletionRequests`
- `lookbookDeletionAuditLogs`
- `lookbookExtractionDiagnostics`
- `users/{uid}/brandStates`
- `users/{uid}/seasonStates`
- 확실하지 않음: post/comment state 컬렉션 경로는 관련 Repository와 rules를 재확인해야 한다.

브랜드 관리:

- 총 관리자 source는 `brandAdmins/{uid}` 문서다.
- 총 관리자는 `brandAdmins/{uid}.isActive == true`일 때만 유효하다.
- `brandAdmins.roles`는 표시/감사용 선택 필드이며 권한 판단 source로 사용하지 않는다.
- `brandAdmins`의 예전 `canCreateBrands`, `brandCreator`, `allowedBrandIDs` 성격의 필드는 권한 판단 source로 사용하지 않고 운영 문서에서 제거한다.
- `brands/{brandID}`는 브랜드 기본 정보를 가진다.
- 브랜드별 owner/admin source는 `brands/{brandID}/admins/{uid}` 문서다.
- 브랜드 owner/admin은 `brands/{brandID}/admins/{uid}.role in ["owner", "admin"]`일 때만 유효하다.
- `brands/{brandID}.ownerUIDs/adminUIDs` 배열은 legacy 모델이며 신규 권한 판단 source로 사용하지 않는다.
- 주요 필드:
  - `name`
  - `normalizedName`
  - `englishName`
  - `normalizedEnglishName`
  - `websiteURL`
  - `lookbookArchiveURL`
  - `logoPath`
  - `logoThumbPath`
  - `logoDetailPath`
  - `logoOriginalPath`
  - `isFeatured`
  - `deletionStatus`: `active | deletionRequested`
  - `deletionRequestedAt`
  - `deletionRequestedBy`
  - `deletionReason`
  - `restoreUntil`
  - `purgeAfter`
  - `deleteRequestID`
  - `updatedBy`
  - `updatedAt`
- 룩북 import 진단 Phase 1 계약 source of truth는 `docs/ai/tasks/lookbook-import-diagnostics/phase-1-data-api-contract.md`다.
- 브랜드 문서에는 최신 시즌 목록 추출 진단 포인터를 추가한다.
  - `lastSeasonDiscoveryDiagnosticID`
  - `lastSeasonDiscoveryStatus`: `passed | failed | needsReview`
  - `lastSeasonDiscoveryCandidateCount`
  - `lastSeasonDiscoverySuggestedFixScope`: `common_logic | brand_adapter | unknown`
  - `lastSeasonDiscoveryAt`
  - `lastSeasonDiscoveryErrorMessage`
- `brands/{brandID}/admins/{uid}` 주요 필드:
  - `uid`
  - `brandID`
  - `role`
  - `email`
  - `normalizedEmail`
  - `addedBy`
  - `addedAt`
  - `updatedAt`
- 브랜드명 중복 방지는 `brandNameIndex/{normalizedName}`과 `brandNameIndex/{normalizedEnglishName}`으로 처리한다.
- 브랜드명/영문명 변경은 `updateBrand` callable transaction에서 새 index 중복 검증, 이전 index 삭제, 브랜드 문서 갱신을 함께 처리한다.
- `isFeatured` 변경은 총 관리자만 가능하다.
- 총 관리자는 브랜드 owner가 아니어도 브랜드명, 영문 브랜드명, 공식 홈페이지 URL, 룩북 목록 URL, 로고 경로, 시즌/포스트/커버 업로드를 관리할 수 있다.
- 브랜드 owner/admin은 브랜드명, 영문 브랜드명, 공식 홈페이지 URL, 룩북 목록 URL, 로고 경로, 시즌/포스트/커버 업로드를 관리할 수 있다.
- 브랜드 관리자 추가/삭제는 `addBrandManager`/`removeBrandManager` callable이 normalized email로 `users.email`을 조회해 대상 UID를 찾고 `brands/{brandID}/admins/{uid}`를 갱신한다.
- 총 관리자는 owner/admin을 추가/삭제할 수 있다.
- 브랜드 owner는 해당 브랜드 admin만 추가/삭제할 수 있다.
- 브랜드 admin은 관리자 추가/삭제 권한이 없다.
- 마지막 owner 삭제는 서버에서 차단한다.

룩북 import 진단:

- 진단 문서는 `lookbookExtractionDiagnostics/{diagnosticId}`에 저장한다.
- 앱은 진단 문서를 직접 Firestore read하지 않고 callable로 최신 진단 1개만 조회한다.
- callable은 `runLookbookExtractionDiagnostic`, `getLatestLookbookExtractionDiagnostic`로 둔다.
- 이력 목록 API는 1차 구현에서 만들지 않는다.
- 진단 유형은 `season_discovery | season_image_import`다.
- 진단 상태는 `passed | failed | needsReview`다.
- `brands/{brandID}/importJobs/{jobID}`에는 최신 시즌 이미지 import 진단 포인터를 추가한다.
  - `lastImageImportDiagnosticID`
  - `lastImageImportDiagnosticStatus`: `passed | failed | needsReview`
  - `lastImageImportDiagnosticAt`
- 시즌 목록 추출 성공 시 worker 후보는 `brands/{brandID}/seasonCandidates/{candidateID}`에 upsert한다. 앱은 성공 요약을 별도로 보여주지 않고 candidate 목록을 바로 표시한다.
- 시즌 목록 추출 실패 시 앱은 과거 candidate를 fallback으로 보여주지 않는다. 실패 화면에는 불러온 시즌 수와 `재시도`만 노출하고, 원인/추천 수정 범위는 진단 문서와 운영 로그에서 확인한다.
- 시즌 이미지 import 진단의 앱 표시 요약은 `이미지 N개 중 M개 완료, F개 실패` 형태이며 URL, HTTP status, 내부 오류 문자열은 관리자 UI에 노출하지 않는다.
- 진단 문서는 90일 보존하고 `cleanupExpiredLookbookExtractionDiagnostics` scheduled cleanup으로 정리한다.
- `lookbookExtractionDiagnostics`는 클라이언트 직접 read/write를 허용하지 않고 callable Functions 경계로 접근한다.

룩북 삭제 lifecycle:

- 브랜드/시즌/포스트 hard delete는 앱 callable로 제공하지 않는다. 영구 삭제는 `purgeExpiredLookbookDeletions` scheduled function만 수행한다.
- 브랜드 삭제 요청은 총 관리자만 가능하며 `brands/{brandID}.deletionStatus = deletionRequested`로 기록한다.
- 시즌과 포스트 삭제 lifecycle은 기존 노출/운영 `status`와 분리된 `deletionStatus`를 사용한다.
- 시즌 삭제 시 `brands/{brandID}/seasons/{seasonID}.deletionStatus = deleted`로 기록하고, 하위 포스트 문서를 즉시 `deleted`로 변경하지 않는다.
- 포스트 삭제 시 `brands/{brandID}/seasons/{seasonID}/posts/{postID}.deletionStatus = deleted`로 기록한다.
- iOS DTO decode는 기존 문서 호환을 위해 `deletionStatus`가 없으면 `active`로 처리한다.
- 사용자 목록/탭/검색/좋아요 리스트는 삭제 상태 대상을 비노출한다.
- 공유/딥링크/좋아요 상세 직접 진입은 부모 브랜드/시즌/포스트 삭제 상태를 확인하고 unavailable 상태로 처리한다.
- 일반 사용자 unavailable 화면에는 삭제 요청 `reason`/메모 원문을 노출하지 않는다. 메모는 관리자 삭제 관리 화면 전용이다.
- 브랜드 삭제 요청/취소 UI와 브랜드 `deletionRequested` 상태 노출은 총 관리자에게만 제공한다.
- 브랜드 owner/admin은 권한 있는 브랜드의 시즌/포스트 삭제와 복구만 할 수 있다.
- 시즌/포스트 다중 삭제 요청은 callable Functions `batchSoftDeleteSeasons`, `batchSoftDeletePosts`로 처리한다.
  - 한 번에 최대 20개 target을 받는다.
  - 각 target은 항목별 transaction으로 처리하며 일부 실패 시 응답 `results`에 항목별 성공/실패를 반환한다.
  - batch 성공 항목도 단건 삭제와 동일하게 원본 문서 상태, `lookbookDeletionRequests` projection, `lookbookDeletionAuditLogs` 감사 로그를 갱신한다.
- 복구 가능 기간은 7일이며 `restoreUntil`과 `purgeAfter`에 같은 timestamp를 기록한다.
- scheduled purge는 `Asia/Seoul` 기준 매일 04:00 실행한다. 20개는 active/failed 독립 query의 page 크기이며 전체 실행 처리량 상한이 아니다.
- scheduled purge는 `brand -> season -> post` 순서로 target type별 cursor를 소진하고, 같은 브랜드는 순차 처리하며 서로 다른 브랜드만 최대 3개 병렬 처리한다.
- `active` 대상은 `status = active`, `targetType`, `purgeAfter <= now` 조건으로 조회한다.
- 자동 재시도 대상은 `status = failed`, `autoRetryEligible = true`, `targetType`, `purgeAfter <= now`, `retryAfter <= now` 조건으로 Firestore에서 직접 조회한다. 최대 시도 횟수와 실행 직전 eligibility는 claim transaction에서 다시 검증한다.
- 실행 후 7분부터 신규 purge claim을 시작하지 않고 이미 시작한 purge는 완료를 기다린다. cursor 미소진, 시간 종료 또는 lease skip은 잔여 candidate로 기록한다.
- 삭제 요청 projection은 `lookbookDeletionRequests/{requestID}`에 둔다.
- `lookbookDeletionRequests/{requestID}` 주요 필드:
  - `requestID`
  - `targetType`: `brand | season | post`
  - `targetID`
  - `targetPath`
  - `brandID`
  - `seasonID`
  - `postID`
  - `status`: `active | cancelled | restored | purged | failed`
  - `requestedBy`
  - `requestedAt`
  - `restoreUntil`
  - `purgeAfter`
  - `reason`
  - `cancelledBy`
  - `cancelledAt`
  - `restoredBy`
  - `restoredAt`
  - `updatedBy`
  - `updatedAt`
  - `purgeAttemptCount`
  - `lastPurgeAttemptAt`
  - `retryAfter`
  - `autoRetryEligible`
  - `purgedAt`
  - `purgedBy`
  - `purgeErrorMessage`
  - `manualRetryState`: `queued | running | failed | null`
  - `manualRetryToken`
  - `manualRetryCount`
  - `manualRetryRequestedAt`
  - `manualRetryRequestedBy`
  - `purgeLeaseToken`
  - `purgeLeaseUntil`
  - `purgeExecutionSource`: `scheduled | manual | null`
  - `lastPurgeClaimedAt`
  - `targetDisplayName`
  - `targetImagePath`
  - `brandName`
  - `brandEnglishName`
  - `brandLogoThumbPath`
  - `seasonTitle`
  - `seasonCoverThumbPath`
  - `postCaption`
  - `postImageThumbPath`
- 표시용 snapshot 필드는 신규 삭제 요청부터 저장한다. 기존/부분 projection에는 없을 수 있으므로 `listLookbookDeletionRequests` callable이 원본 브랜드/시즌/포스트 문서를 읽어 응답 summary만 보강한다. `targetDisplayName`이 "삭제된 브랜드/시즌/포스트" fallback이더라도 `brandName`/`seasonTitle`/`postCaption`이 있으면 target별 snapshot 이름을 응답 제목으로 보강한다. 시즌명 snapshot은 시즌 문서의 `displayTitle`, legacy `title`, `sourceTitle` 순서로 읽는다. 이 보강은 `lookbookDeletionRequests` 문서 자체를 backfill write하지 않는다.
- 클라이언트 목록 제목은 target별 표시용 snapshot을 우선 사용하고, 값이 없으면 유효한 `targetDisplayName`을 사용한다. `postCaption`이 없는 포스트는 서버 snapshot의 `targetDisplayName = "포스트"`를 표시할 수 있다. snapshot이 모두 없을 때만 "삭제된 시즌"처럼 사람이 읽을 수 있는 fallback을 표시한다. `targetID`/UID는 제목 fallback으로 쓰지 않는다.
- 앱 삭제 요청 목록은 `active/failed`만 표시하고 `purged` projection은 서버 운영 이력으로만 유지한다. 별도 이미지 파일은 보존하지 않는다.
- 삭제/복구/취소 감사 로그는 `lookbookDeletionAuditLogs/{logID}`에 둔다.
- `lookbookDeletionAuditLogs/{logID}` 주요 필드:
  - `action`
  - `requestID`
  - `targetType`
  - `targetID`
  - `targetPath`
  - `brandID`
  - `seasonID`
  - `postID`
  - `actorUID`
  - `reason`
  - `before.deletionStatus`
  - `after.deletionStatus`
  - `createdAt`
- 클라이언트는 `lookbookDeletionRequests`와 `lookbookDeletionAuditLogs`를 직접 read/write하지 않고 callable Functions를 사용한다.
- failed purge manual retry 요청은 총 관리자 callable `retryFailedLookbookDeletionPurge`만 생성한다. 새 request를 만들지 않고 기존 requestID에 새 token과 `queued` 상태를 기록한다.
- `onLookbookDeletionManualRetryQueued` trigger는 token 변경 + queued 상태에서 즉시 purge를 시작한다.
- purge 동시 실행 잠금은 `lookbookDeletionPurgeLeases/{brandID}`에 둔다. 주요 필드는 `leaseToken`, `leaseUntil`, `requestID`, `brandID`, `source`, `claimedAt`이다.
- lease는 15분이며 request의 `purgeLeaseToken`과 lease 문서 token이 모두 실행 token과 일치할 때만 finalize한다.
- 브랜드 단위 lease로 같은 브랜드의 브랜드/시즌/포스트 purge를 직렬화한다. lease collection은 클라이언트 직접 접근을 허용하지 않는다.
- manual trigger가 실행되지 않거나 timeout되면 `autoRetryEligible = true`, `retryAfter = now`인 기존 scheduler query가 fallback한다.
- iOS 앱은 `LookbookDeletionRepositoryProtocol` / `CloudFunctionsLookbookDeletionRepository`를 통해 삭제 lifecycle callable을 호출한다.
- `firestore.rules`는 `lookbookDeletionRequests`, `lookbookDeletionAuditLogs` 직접 접근을 막고, 시즌/포스트 직접 `delete`를 막으며 기존 create/update 권한은 유지한다.
- scheduled/manual purge 성공 시 projection status는 `purged`가 되고 `purgedAt`, `purgedBy = "system"`을 기록한다.
- scheduled/manual purge 실패 시 projection status는 `failed`가 되고 `purgeAttemptCount`, `lastPurgeAttemptAt`, `retryAfter`, `autoRetryEligible`, `purgeErrorMessage`를 기록한다. 3회 실패 후 자동 재시도 대상에서 제외한다.
- 브랜드 purge는 `brands/{brandID}` 문서와 모든 하위 subcollection, 해당 브랜드의 `brandNameIndex` 문서, brand/season/post/comment user state projection, `brands/{brandID}/` Storage prefix를 삭제한다.
- 시즌 purge는 시즌 문서와 하위 posts/comments/replacements, 관련 season/post/comment user state projection, `brands/{brandID}/seasons/{seasonID}/` Storage prefix를 삭제한다.
- 포스트 purge는 포스트 문서와 하위 comments/replacements, 관련 post/comment user state projection, `brands/{brandID}/seasons/{seasonID}/posts/{postID}/` Storage prefix를 삭제한다.
- 부모 target purge가 성공하면 같은 범위의 하위 active/failed deletion request projection도 `purged`로 닫는다.
- 문서 필드에 저장된 Storage 경로는 raw Storage path만 삭제 대상으로 인정하며, `brands/{brandID}/` 하위 경로인지 검증한 뒤 포함한다. `://`가 들어간 URL, 외부 `remoteURL`, `sourcePageURL`은 삭제하지 않는다.
- purge 대상 조회와 user state projection 정리 인덱스는 `firestore.indexes.json`의 `lookbookDeletionRequests` composite index와 `brandStates`, `seasonStates`, `postStates`, `commentStates` collection group field override를 확인한다. drain query는 active용 `status + targetType + purgeAfter + requestID`, failed용 `status + autoRetryEligible + targetType + purgeAfter + retryAfter + requestID` index를 사용한다.

브랜드 요청:

- 사용자는 브랜드 검색 결과 없음 상태에서 브랜드명을 요청한다.
- 요청 생성/조회/관리 경계는 callable Functions다.
- 클라이언트는 `brandRequests` 계열 컬렉션을 직접 read/write하지 않는다.
- `brandRequests/{requestID}`는 사용자별 개인 요청 기록이다.
- 요청 처리 상태의 source는 `brandRequestNameIndex/{dedupeKeyHash}` group 문서다.
- `listMyBrandRequests`는 사용자 요청 문서를 조회하되 group 상태를 함께 반영해 최신 사용자 노출 상태를 반환한다.
- `requestID`는 같은 사용자 + 같은 dedupe key 중복 요청을 막기 위해 deterministic ID를 사용한다.
- 사용자 노출 상태는 `submitted`, `reviewing`, `added`, `rejected`다.
- 운영자 내부 단계는 `requested`, `processing`, `completed`, `rejected`다.
- 관리자 기본 처리 이력 노출 기간은 14일이다.
- `listBrandRequestGroups`의 `processedScope = recent`는 `rejected/completed` group 중 최근 14일 이력을, `history`는 14일 이전 이력을 조회한다.
- `listLookbookDeletionRequests`는 서버에서 `status in [active, failed]`를 고정 적용한다. 서버는 삭제 요청 조회의 `status/statusGroup/processedScope/recentProcessedDays`를 소비하지 않는다. `targetType`, `brandID`, `limit`, cursor를 지원하고 `limit + 1` query로 실제 다음 page가 있을 때만 `nextCursor`를 반환한다. iOS wrapper도 같은 단순화 계약을 사용한다. `purged/cancelled/restored` projection과 감사 로그는 서버 운영 이력으로 유지하지만 앱 목록 API에는 반환하지 않는다.
- `spam`은 운영자 단계가 아니라 `rejectionReason = spam`으로 기록한다.
- 사용자 `진행 중` 목록은 `submitted`, `reviewing`만 보여주고, `added`, `rejected`는 즉시 `이전 요청` 목록으로 이동한다.
- `brandRequestNameIndex/{dedupeKeyHash}`는 전체 요청 수요와 운영 group을 집계한다.
- `brandRequestNameIndex/{dedupeKeyHash}.createdBrandID`는 처리중 단계에서 브랜드 생성은 끝났지만 검수 완료 전인 중간 연결이다.
- `brandRequestNameIndex/{dedupeKeyHash}.brandCreatedAt`, `brandCreatedBy`는 해당 중간 브랜드 생성 감사 필드다.
- `brandRequestNameIndex/{dedupeKeyHash}.resolvedBrandID`는 검수 후 완료 처리된 최종 연결이다.
- dedupe key는 `englishBrandName`이 있으면 normalized english name, 없으면 normalized brand name이다.
- 원본 normalized brand name은 문서 필드 `normalizedBrandName`에 저장한다.
- 선택 영문 브랜드명은 `englishBrandName`, `normalizedEnglishBrandName`에 저장한다.
- 사용자당 하루 5건 제한은 `brandRequestDailyCounters/{uid}/brandRequestDays/{yyyyMMdd}`로 관리한다.
- `brandRequestDays` 문서에는 `expiresAt`을 기록하고, Firestore TTL policy 대상 field로 사용한다.
- spam/차단 상태는 `brandRequestUserLimits/{uid}`에 저장한다.
- spamCount 3회 이상은 7일 차단, 5회 이상은 30일 차단, 10회 이상은 영구 차단 후보로 처리한다.

좋아요/상호작용 상태:

- 브랜드 좋아요는 `BrandUserState`와 `users/{uid}/brandStates` 흐름을 사용한다.
- 시즌 좋아요는 `SeasonUserState`, `setSeasonEngagement`, `users/{uid}/seasonStates` 흐름을 사용한다.
- 포스트/댓글 상호작용은 `PostUserState`, `CommentUserState`, 관련 engagement repository/usecase 흐름을 확인한다.

런타임 공유 상태:

- `LookbookInteractionStore`: 브랜드/시즌/포스트/댓글 상호작용 상태 공유.
- `BrandInteractionStore`, `SeasonInteractionStore`, `PostInteractionStore`, `CommentInteractionStore`: 상호작용 상태 관리.
- `PinAwareInteractionCache`: pin 범위가 필요한 상호작용 캐시.
- `LookbookDebugFailureInjectionStore`: 테스트/디버그 실패 주입.

## Firebase Functions 데이터 흐름

주요 callable/trigger는 `functions/src/index.ts`에 export된다.

주요 영역:

- Auth: Kakao token exchange
- Brand admin/capability
- Brand request create/list/manage
- Brand/Post/Season/Comment engagement
- Comment create/reply/delete/report
- User block/hidden author filtering
- Season import request/process/materialize/asset sync/candidate discovery
- Chat room close trigger

데이터 변경이 있는 callable은 클라이언트 ViewModel에서 직접 호출하지 않고 Repository/UseCase 경계를 통해 사용한다.

## Firestore rules/indexes

- rules: `firestore.rules`
- indexes: `firestore.indexes.json`

보안 규칙이나 인덱스를 바꾸는 작업은 `firestore-workflow` 절차를 확인한다.

## 새 데이터 모델 추가 기준

새 데이터 모델을 추가하기 전에 아래를 확인한다.

- Domain entity와 외부 DTO를 분리할 필요가 있는가?
- Repository protocol과 implementation 경계가 필요한가?
- UseCase로 묶어야 하는 비즈니스 흐름인가?
- Firestore rules/indexes 변경이 필요한가?
- 운영 데이터 마이그레이션이나 기존 문서 호환성이 필요한가?
- 모호한 항목이 있으면 사용자와 논의한다.
