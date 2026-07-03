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
- 앱이 아직 배포/운영 중이지 않고 데이터가 작으므로 legacy compatibility는 고려하지 않고 제거한다. 필요한 개발 데이터 정리는 사용자가 수동으로 처리한다.
- Firestore membership source는 `Rooms/{roomID}/members/{uid}` 문서 존재 여부다.
- GRDB/local cache는 전체 room membership replica로 사용하지 않는다. 최근 메시지 sender nickname/avatar 표시를 위한 bounded profile cache로 의미를 축소한다.
- GRDB `RoomMember` table은 migration chain 호환 흔적으로 남아 있지만 production 참여자 목록 source나 write API로 사용하지 않는다.

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
- `brands/{brandID}/seasons`
- `brands/{brandID}/seasons/{seasonID}/posts`
- `users/{uid}/brandStates`
- `users/{uid}/seasonStates`
- 확실하지 않음: post/comment state 컬렉션 경로는 관련 Repository와 rules를 재확인해야 한다.

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
