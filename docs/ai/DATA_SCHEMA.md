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

확실하지 않음:

- 사용자 Firestore 컬렉션 전체 스키마는 아직 이 문서에서 완전히 검증하지 않았다.

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
