# Lookbook Entrypoints

- PR 리뷰의 선로딩 경로 갱신: `AvatarViewportObserver.onChange(of: items)` → `update(items:)`에 콜백의 최신 배열을 전달한다. 행 ID/좌표가 그대로인 프로필 경로 변경도 스크롤 없이 요청한다. 재현 테스트는 `AvatarNestedViewportTests.testSwiftUIViewportPrefetchesChangedPathWithoutScrolling`, 근거는 [리뷰 기록](../tasks/avatar-image-loading/review.md).

- 댓글 빠른 스크롤 표시: `CommentSafetyAvatarView.displayedImage`는 현재 표시 이미지가 없을 때 보호된 기존 메모리 캐시를 첫 body에서 즉시 확인한다. `AvatarImagePresentationState.configure(initialImage:)`도 UIKit/SwiftUI에 즉시 이미지를 전달하되 기존 async loader는 유지해 disk promotion을 생략하지 않는다. 서비스/메모리 용량을 추가하지 않는다.

- 답글 시트 높이: `PostCommentsSheetView.repliesSheet`는 iOS16+에서 62%와 large 두 detent를 제공해 상단 손잡이로 확장 가능하다. 사용자 실기기 QA의 작은 답글 영역 불편을 반영했으며 원댓글/입력창 구성은 유지한다.

- 댓글 아바타 경로 갱신: `CommentSafetyAvatarView.onChange(of: identity)`는 콜백의 새 identity를 `configure(_:)`에 직접 전달한다. 이전 View의 빈 path 재적용으로 상단 초기 행이 스크롤 전까지 기본 사진에 머물던 실기기 QA 결함 수정이며, 재진입 검증 기록은 Phase5 문서를 참조한다.

- 2026-09-20 재진입 상단 아바타 미표시 수정은 사용자 실기기 정상 및 상단4행 새 identity→start→loaded 로그로 확인했다. 조사용 `avatarSwiftUI.*`/`avatarPresentation.*` 임시 로그는 제거했다. 상세는 avatar-image-loading/progress/phase-5.md.


- 아바타 Phase4: `Views/Shared/AvatarViewportObserver.swift`의 row preference·미배치 행 추정·viewport 수요 → PostCommentsSheetView/PostCommentRepliesSheetView/PostDetailView. 기존 PostComments/PostCommentReplies/PostDetailViewModel의 일괄 선로딩·영구 prefetchedAvatarPaths 제거; 앞의 두 VM 이미지 DI도 LookbookContainer에서 제거. 명시 refresh는 서비스 실패 경로를 한 번 해제한 뒤 환경 refreshID로 보이는 avatar와 선로딩을 재시도한다. [구현·제약](../tasks/avatar-image-loading/progress/phase-4.md).

- 댓글·답글·안전 sheet 아바타는 `Views/PostDetail/CommentSafetyAvatarView.swift`로 통일했다. PostCommentCardView와 CommentBlock/Delete/ReportSheet가 사용자ID·경로를 전달하며, StateObject의 AvatarImagePresentationState가 완료/실패와 취소를 관리한다. 요청 전 loadedPath 마킹 없음. 출발 memoryOnly 정책은 Phase2 DI 유지. [Phase3](../tasks/avatar-image-loading/progress/phase-3.md).

- 이미지 로딩 최종 구조·실기기 비교는 [공개 검증 요약](../qa-image-loading-concurrency-2026-09-16.md) 참조. HTTP 디스크 히트도 본문 읽기 전에 디코딩 바이트를 예약한다. 예약 대기 중 캐시 제거는 `LookbookHTTPImageCacheTests.diskBodyWaitsForDecodeBudgetBeforeReadingAndHandlesEviction`에서 검증한다.

- Phase 5 재시도 QA: Debug `LookbookUITestFixtureRepositoryProvider.swift`의 `--uitest-lookbook-image-fail-once`가 브랜드/시즌/포스트 각 Storage 경로의 첫 로드만 실패시킨다. 해당 fixture의 prefetch는 no-op으로 유지해 표시 요청 실패가 확정적으로 보인다. `LookbookSmokeUITests.testImageRetryDoesNotOpenCardDetail`은 재시도가 카드 이동 없이 복구되는지 확인한다. 일반 서버·화면 로딩 정책은 변경하지 않았다. [실행 결과](../tasks/image-loading-stage-concurrency/phase-5-validation.md).

- 이미지 Phase 4: `Views/Shared/LookbookViewportObserver.swift`가 세 화면의 카드 frame·화면 높이·스크롤 방향을 받아 미배치 행 위치를 추정한다. `LookbookHomeView`/`BrandDetailView`/`SeasonDetailView` → 각 ViewModel `updateViewport` → `Services/ImageLoading/LookbookImagePrefetchController.swift`가 이미지 수요를 추가/300ms 후 해제한다. 홈은 끝 카드 표시 전 page 요청, 시즌은 기존 page24/cursor 계약 유지. `BrandRowView.swift`와 `Views/Shared/LookbookAssetImageView.swift`가 이미지 실패 재시도와 이전 응답 차단을 소유한다. DI/Coordinator·서버 API 변경 없음. [시작값·QA](../tasks/image-loading-stage-concurrency/phase-4-lookbook-screens.md).


- 이미지 Phase 3: `Services/ImageLoading/LookbookAssetImageRequest.swift`가 primary/secondary Storage·remoteURL·Referer 후보를 정규화하고 `BrandDetailViewModel`/`SeasonDetailViewModel` 프리패치 및 `Views/Shared/LookbookAssetImageView.swift` 표시가 공유한다. `BrandImageCacheProtocol`/`BrandImageCache.swift`는 prefetchAssets와 HTTP 갱신 API 경계다. `LookbookHTTPImageCache.swift`가 URL·Referer·maxBytes identity, memory/disk body+metadata, max-age/no-cache/no-store, ETag/Last-Modified 304/200, 일시/영구 오류와 중복 검증·취소를 소유한다. `ImagePipelineResources.shared`의 network/decode/I/O·바이트 예산을 공유한다. 좋아요/시즌·포스트 카드/포스트 상세는 공용 View를 통해 적용된다. [구현 정책과 한계](../tasks/image-loading-stage-concurrency/phase-3-http-cache.md). 화면 viewport/목록 선표시는 Phase4.


- 아모멘토 cold QA: 예약8/8→8/16→16/16MiB 비교, 마지막값을 후속 시작값으로 유지. 시즌목록 initial prefetch 대기는 아직 Phase4 대상. 사용자 체감 차이 없음. [비교 결과](../tasks/image-loading-stage-concurrency/phase-2-qa.md).

- Cold QA: BrandDetailViewModel의 metadata→initial prefetch await→seasons 공개 순서가 남아 있다(Phase4 목록 선표시 대상). ImagePipelineProcessor에 성공 body 바이트 계측을 보완했다. [삭제·재설치 관찰과 연결 상태](../tasks/image-loading-stage-concurrency/phase-2-qa.md).

- 2026-09-16 이미지 Phase 2: LookbookRepositoryProvider/BrandImageCache의 Data/file fetcher → LookbookStorageService → FirebaseImageDownload. 작은 썸네일은 byte 예약·네트워크·준비 gate, 큰 허용 크기는 임시 파일. 공용 저장은 표시와 분리. 관리자 LookbookRemotePreviewImageLoader도 파일 전송 지원. 외부 URL 폴백 TTL/통합·화면 프리패치는 Phase3/4. [구현·초기값·QA](../tasks/image-loading-stage-concurrency/phase-2-implementation.md).

- 확대 화면: `Views/PostDetail/PostImagePreviewView.swift`의 `LookbookImageViewerView` → 공용 `SimpleImageViewerVC`/`ImageViewerChromeView`. 패션 매거진 컨트롤·로딩/실패/저장 상태 공유, 한 장이면 번호 숨김, 기존 원본 loader와 onClose 유지. 검증은 `tasks/shared-image-viewer-editorial/implementation-plan.md`.

## 목적과 탐색 순서

Lookbook 변경 시 필요한 코드만 찾기 위한 인덱스다.

1. 화면/사용자 흐름 변경: 이 문서의 화면 표
2. 데이터/API 변경: `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/FIREBASE.md`
3. 장기 기술 결정: `docs/ai/ADR.md`
4. 완료 상태·QA: 관련 task의 `progress.md`, `qa-checklist.md`

## 공통 조립

| 책임 | 진입점 |
| --- | --- |
| 앱 탭 조립 | `OutPick/Features/Lookbook/LookbookCompositionRoot.swift` |
| Feature DI/factory | `OutPick/Features/Lookbook/LookbookContainer.swift` |
| 화면 전환 | `OutPick/Features/Lookbook/Coordinators/LookbookCoordinator.swift` |
| 댓글 전환 | `OutPick/Features/Lookbook/Coordinators/PostCommentCoordinator.swift` |
| Repository 조립 | `OutPick/Features/Lookbook/Repositories/LookbookRepositoryProvider.swift` |
| SwiftUI environment | `OutPick/Features/Lookbook/Environment` |
| 공용 store | `OutPick/Features/Lookbook/Domains/Stores` |
| DTO/mapper | `OutPick/Features/Lookbook/Models` |
| 이미지/미디어 | `OutPick/Features/Lookbook/Services` |

- Lookbook/Liked root는 UIKit navigation stack 위 SwiftUI Hosting 구조다.
- 상세 push/pop은 SwiftUI hidden route가 아니라 `LookbookCoordinator`가 소유한다.
- Lookbook/Liked root navigation stack은 `LookbookNavigationController`가 소유한다. Coordinator가 push하는 SwiftUI 화면은 화면별 `LookbookInteractivePopState`를 가진 `LookbookHostingController`로 감싼다.
- browse route는 edge/content pop을 허용하고, 작성 초안·관리자 내부 단계·mutation 상태는 `lookbookInteractivePopDisabled(_:)`로 동적으로 차단한다.
- 브랜드 요청, 삭제 관리, extraction 검토, 시즌 보수와 `AdminBrandManagementView`가 stateful 정책 대상이다. `AdminBrandManagementView` 내부 메뉴의 실제 push route 전환은 후속 작업이다.
- extraction 부족 이미지 보고가 저장되어 `correctionRequired`로 전환된 뒤에는 입력 폼이 더 이상 초안이 아니므로 interactive-pop 차단을 해제한다.
- `DefaultAppContentRouter`의 룩북 상세·브랜드 요청 내역 진입도 HostingController를 직접 만들지 않고 `LookbookCoordinator` push를 사용한다.
- View는 Repository/Firebase를 직접 만들지 않고 Container가 주입한다.
- SwiftUI 입력 화면 키보드 dismiss는 `KeyboardDismissSupport.outpickDismissKeyboardOnTap()`을 사용한다.
- Firestore 기본 identity는 ADR-020에 따라 문서 경로 ID를 사용한다. 앱의 Season DTO/Repository는 read-only이며 생성은 import worker의 Admin SDK materialization만 사용한다.

## Firestore 문서 ID 경계

| 확인할 내용 | 코드 진입점 |
| --- | --- |
| read schema와 DTO→Domain mapping | `OutPick/Features/Lookbook/Models/DTOs/`; identity가 필요한 mapper의 `toDomain(documentID:)` |
| snapshot 경로 ID 전달 | `OutPick/Features/Lookbook/Repositories/Implementations/Firestore*Repository.swift` |
| 브랜드·시즌·포스트 기본 identity | `BrandDTO.swift`, `SeasonDTO.swift`, `PostDTO.swift`와 각 Firestore Repository |
| 댓글·replacement 기본 identity | `CommentDTO.swift`, `ReplacementDTO.swift`와 `FirestoreCommentRepository.swift`, `FirestoreReplacementRepository.swift` |
| 태그 기본 identity | `TagDTO.swift`, `FirestoreTagRepository.swift` |
| import job·candidate 기본 identity | `SeasonImportJobDTO.swift`, `SeasonCandidateDTO.swift`와 각 Firestore Repository |
| Season 생성·무드 수정 | worker `processor.ts`의 create, `updateSeasonMoods` callable의 기존 문서 patch |
| 경계 회귀 테스트 | `OutPickTests/FirestoreDocumentIDBoundaryTests.swift` |

Repository가 `DocumentSnapshot.documentID`를 같은 snapshot에서 decode한 DTO와 함께 mapper에 전달한다. 자기 문서 ID는 DTO 필드로 중복 저장하지 않으며, `brandID`, `postID`, `userID`처럼 부모 경로나 별도 query 계약을 나타내는 ID는 해당 데이터 계약대로 유지한다.

## 화면별 진입점

| 변경 목적 | View | ViewModel/상태 |
| --- | --- | --- |
| 홈·검색 | `Views/LookbookHome/LookbookHomeView.swift` | `ViewModels/LookbookHomeViewModel.swift` |
| 관심 스타일 브랜드 전체 보기 | `Views/LookbookHome/InterestedStyleBrandListView.swift` | `ViewModels/InterestedStyleBrandListViewModel.swift` |
| 브랜드 요청 | `Views/BrandRequest` | `BrandRequestViewModel.swift`, `MyBrandRequestsViewModel.swift` |
| 브랜드 상세 | `Views/BrandDetail/BrandDetailView.swift` | `BrandDetailViewModel.swift` |
| 시즌 상세 | `Views/SeasonDetail/SeasonDetailView.swift` | `SeasonDetailViewModel.swift` |
| 포스트·댓글 | `Views/PostDetail` | `PostDetailViewModel.swift`, `PostCommentsViewModel.swift` |
| 좋아요 | `Views/Liked` | `LikedViewModel.swift` |
| 브랜드 생성 | `Views/CreateBrand/brand` | `CreateBrandViewModel.swift`, `CreateBrandFlowView.swift` |
| 관리자 홈 | `Views/Admin/LookbookAdminHomeView.swift` | `BrandAdminSessionStore` |
| 스타일 무드 관리 | `Features/StyleMood/Views/StyleMoodManagementView.swift` | `StyleMoodManagementViewModel.swift` |
| 브랜드 요청 관리 | `Views/Admin/AdminBrandRequestGroupsView.swift` | `AdminBrandRequestGroupsViewModel.swift` |
| 브랜드 관리 | `Views/Admin/AdminBrandManagementView.swift` | `AdminBrandManagementViewModel.swift` |
| 삭제 관리 | `Views/Admin/AdminLookbookDeletionManagementView.swift` | `AdminLookbookDeletionManagementViewModel.swift` |
| 시즌 discovery·import 통합 현황 | `Views/BrandDetail/SeasonImportManagementView.swift` | `SeasonImportManagementViewModel.swift` |
| 시즌 동일성 후보 검토 | `Views/BrandDetail/SeasonDiscoveryReviewView.swift` | `SeasonDiscoveryReviewViewModel.swift` |
| extraction 검토 | `Views/BrandDetail/LookbookExtractionReviewView.swift` | `LookbookExtractionReviewViewModel.swift` |
| 기존 시즌 보수 | `Views/BrandDetail/LookbookSeasonRepairView.swift` | `LookbookSeasonRepairViewModel.swift` |

경로 prefix는 `OutPick/Features/Lookbook/`이다.

- Phase 6 댓글·답글 생성 경로는 ViewModel이 본문별 pending UUID를 소유하고 `CreatePostCommentUseCase`/`CreateCommentReplyUseCase` → `CommentWritingRepositoryProtocol` → `CloudFunctionsCommentWritingRepository`로 전달한다. 같은 본문 네트워크 재시도는 UUID를 유지하고 입력 변경·성공·화면 종료 뒤 새 작성은 새 UUID를 쓴다.
- 댓글 입력은 trim 후 UTF-16 1,000 code unit 상한이며 `PostCommentInputBarView`가 길이 표시 없이 초과 입력을 막는다. 서버의 최종 상한·멱등·분당 20회 합산 quota는 `functions/src/lookbook/comments/{contracts,service}.ts`가 소유한다.
- 댓글·답글 텍스트 의미 자동 필터는 두지 않고 기존 신고·차단·운영자 검수 흐름을 유지한다. 현재 comment attachment는 빈 배열인 텍스트 전용이다.

- 시즌 후보 카드의 대표 이미지는 기존 nullable `coverImageURL`과 placeholder를 그대로 사용한다. Phase 7 backend는 목록 이미지 우선, 시즌 상세 콘텐츠 영역의 최상단 첫 유효 이미지 차선으로 URL을 채우며 SwiftUI 화면·Coordinator·DI는 변경하지 않는다. Worker 진입점은 `extraction/{image-candidates,season-cover}.ts`와 `season-discovery.ts`이고 상세 계약은 task의 `phase-7-season-cover-enrichment.md`다.

### 좋아요 탭

- 화면 조립: `LookbookCompositionRoot.makeLikedRoot` → `LookbookContainer.makeLikedView` → `Views/Liked/LikedView.swift`
- 카드: `LikedBrandCardView.swift`, `LikedSeasonCardView.swift`, `LikedPostCardView.swift`
- 표현 계약: `SAVED EDITS` 헤더, serif 섹션 제목, monospaced 인덱스·카운트, hairline 구분선과 작은 모서리를 사용한다. 브랜드는 정방형 가로 카드, 시즌은 세로형 가로 카드, 포스트는 2열 타이트 그리드다.
- 상태 계약: `LikedViewModel`의 브랜드·시즌·포스트 `SectionState`를 독립 렌더링한다. 부분 실패가 다른 섹션을 가리지 않으며 섹션 패널에서 전체 reload를 재시도한다.
- 동작 계약: pull-to-refresh, 섹션별 pagination, 좋아요 취소, 상세 push는 기존 ViewModel/UseCase/Repository/Coordinator 경계를 유지한다.

### 브랜드 생성과 로고

- 흐름: `CreateBrandFlowView` → `CreateBrandView` → `CreateBrandViewModel.saveBrand()` → `CloudFunctionsBrandStore.createBrand` → `LookbookStorageService` → `CloudFunctionsBrandStore.updateLogoPaths`.
- 완료 기준: 로고를 선택한 경우 `brands/{brandID}/logo/thumb.jpg`, `detail.jpg` 업로드와 두 경로의 단일 패치가 모두 성공해야 생성 완료 단계로 이동한다.
- 실패 기준: 업로드 또는 경로 패치 실패 시 성공한 업로드 객체를 rollback하고, 생성된 브랜드 ID를 `createdBrandDocument`로 유지해 같은 문서에 재시도한다. 재시도 중 브랜드 기본 입력은 잠근다.
- 브랜드 생성과 관리자 편집의 로고 실패 문구는 내부 Storage error/path를 노출하지 않고 `로고 저장에 실패했습니다. 다시 시도해주세요.`로 고정한다.
- Storage 권한: `storage.rules`의 브랜드 쓰기는 계정 문서와 총 관리자/브랜드 관리자 문서만 조회해 Storage rules의 Firestore 교차 조회 2문서 한도를 지킨다. 총 관리자는 신뢰된 운영 주체이므로 별도 브랜드 존재 조회를 하지 않으며, 클라이언트 경로는 생성된 brandID로 고정한다. 실행 프로젝트의 Storage service agent에는 교차 조회용 `roles/firebaserules.firestoreServiceAgent`가 반드시 필요하다.

## 자주 수정하는 흐름

### 관심 스타일 브랜드

읽기 순서:

1. `App/Session/CurrentUserStylePreferenceStore.swift`
2. `Domains/UseCases/LoadInterestedStyleBrandsUseCase.swift`
3. `Repositories/Protocols/BrandRepositoryProtocol.swift`, `Repositories/Implementations/FirestoreBrandRepository.swift`
4. `ViewModels/LookbookHomeViewModel.swift`, `ViewModels/InterestedStyleBrandListViewModel.swift`
5. `Views/LookbookHome/InterestedStyleBrandSectionView.swift`, `InterestedStyleBrandListView.swift`
6. `LookbookContainer.swift`, `Coordinators/LookbookCoordinator.swift`

현재 계약:

- 비공개 `users.selectedMoodIDs`와 공개 `brands.moodIDs`의 교집합을 `array-contains-any`로 조회한다.
- 정렬은 `likeCount DESC`, 문서 ID ASC이며 홈은 10개, 전체 보기는 첫 결과를 이어받아 이후 20개 단위로 조회한다.
- 커서는 `(likeCount, brandID)` field-value keyset이다. append는 브랜드 ID를 중복 제거하고 동일 커서 동시 호출을 막는다.
- `deletionStatus`가 없는 기존 활성 브랜드도 보존하기 위해 query 조건에는 넣지 않고 Domain의 `isVisibleToUsers`로 비노출 문서를 거른다.
- 검색 중에는 섹션을 표시하지 않으며, 조회 실패는 기존 전체 브랜드 목록과 분리해 재시도한다.
- 활성 계정은 관심 스타일을 1~5개 유지하므로 룩북에 편집 CTA를 두지 않는다. 방어적으로 관심 스타일이 0개면 개인화 섹션을 숨기고, 매칭 브랜드가 0개면 중앙 정렬한 안내만 표시하며 요청 CTA는 노출하지 않는다. 관심 스타일 섹션과 세로 목록 사이는 divider와 `전체 브랜드` 헤더로 구분한다.
- `CurrentUserStylePreferenceStore`는 bootstrap·온보딩 완료·마이페이지 저장·로그아웃에 맞춰 갱신되며 홈과 전체 보기의 첫 페이지를 다시 구성한다.
- `popularScore`는 계산·갱신 경로가 없어 Phase 6 정렬에 사용하지 않는다.

### 일반 사용자 브랜드 요청

읽기 순서:

1. `LookbookHomeView.swift`
2. `BrandRequestView.swift`, `MyBrandRequestsView.swift`
3. `LookbookCoordinator.swift`, `LookbookContainer.swift`
4. `MyPageViewController.swift`, `MyPageCoordinator.swift`
5. `AppContentRouting.swift`, `DefaultAppContentRouter.swift`

현재 계약:

- 일반 사용자의 새 브랜드 요청은 룩북 검색 결과가 없을 때만 노출하며, 정규화한 검색어를 요청 화면의 초기 브랜드명으로 전달한다.
- 룩북 홈 상단과 관심 스타일 빈 상태에는 요청 진입점을 두지 않는다. 홈 상단의 관리자 버튼은 총 관리자에게만 유지한다.
- `MyBrandRequestsView`는 진행 중/이전 요청 조회에 집중하며 새 요청 `+` 버튼을 제공하지 않는다.
- 요청 제출 성공 시 기존처럼 현재 요청 화면을 본인 요청 상황 화면으로 교체한다.
- 이후 재진입은 마이페이지 `ACTIVITY > 브랜드 요청 내역`에서 시작하며, `DefaultAppContentRouter.openMyBrandRequests()`가 MyPage navigation stack에 Lookbook 요청 상황 화면을 push한다.
- 총 관리자의 전체 요청 처리 화면은 관리자 콘솔의 브랜드 요청 메뉴로 분리하며 일반 사용자 본인 요청 내역과 혼동하지 않는다.

### 브랜드 상세

읽기 순서:

1. `BrandDetailView.swift`
2. `BrandDetailViewModel.swift`
3. `BrandRepositoryProtocol.swift`, `SeasonRepositoryProtocol.swift`
4. 관련 repository implementation
5. `LookbookContainer.swift`, `LookbookCoordinator.swift`

현재 계약:

- 초기 `Brand` snapshot으로 빠르게 표시한 뒤 단건 브랜드와 시즌 목록을 최신화한다.
- pull-to-refresh는 브랜드, interaction state, 시즌을 함께 갱신한다.
- 삭제 요청 등 사용자 비노출 상태면 상세 상태를 비우고 unavailable을 표시한다.
- 관리자 수정 결과는 `applyUpdatedBrand(_:)`로 상세 상태에 반영한다.
- 이미지 확대는 공용 `LookbookImageViewerView`/Infra UIKit viewer를 사용한다. 선택 이유는 ADR-017.

### 관리자 브랜드 요청

읽기 순서:

1. `AdminBrandRequestGroupsView.swift`
2. `AdminBrandRequestGroupsViewModel.swift`
3. `Domains/Entities/BrandRequest.swift`
4. `ListBrandRequestGroupsUseCase.swift`
5. `BrandRequestRepositoryProtocol.swift`
6. `CloudFunctionsBrandRequestRepository.swift`

현재 계약:

- segment는 `새 요청/처리 중/보류/완료`다.
- `보류/완료`는 최근 14일을 기본 표시하고 이전 기록은 별도 pagination한다.
- 브랜드 생성과 검수 완료는 분리한다.
- 삭제 요청 목록의 `active/failed` 정책과 혼동하지 않는다.

### 관리자 브랜드·시즌 관리

읽기 순서:

1. `AdminBrandManagementView.swift`
2. `AdminBrandManagementViewModel.swift`
3. `Domains/Entities/BrandManagement.swift`
4. 관련 repository/use case
5. `LookbookContainer.swift`

현재 계약:

- 총 관리자와 브랜드 owner/admin 권한을 분리한다.
- 메뉴는 정보, 관리자, `브랜드 스타일`, 시즌 가져오기, 삭제 흐름으로 구성한다. 브랜드 스타일 메뉴는 총 관리자에게만 보인다.
- 총 관리자는 정보 화면에서 브랜드 스타일 0~5개, 브랜드 스타일 메뉴의 시즌 목록에서 시즌 스타일 0~5개를 편집한다.
- 관리자 taxonomy 화면명은 `스타일 키워드 관리`이며 이름·alias 로컬 검색과 빈 그룹 숨김을 지원한다.
- 시즌 목록 검색은 `displayTitle`·`sourceTitle`·`year`·`term`을 대상으로 하고, 시즌 스타일 picker는 키워드 이름·alias를 검색해도 기존 선택 Set을 유지한다.
- 브랜드 생성·편집 picker의 `새 스타일 키워드 추가`는 생성 성공한 키워드를 현재 선택에 즉시 포함한다.
- 브랜드 생성·편집 picker는 전체 키워드를 기본 노출하지 않는다. 검색어가 있을 때만 이름·alias가 일치하는 active 키워드를 표시하고, 선택값은 별도 칩으로 유지하며, 결과가 없고 5개 미만일 때만 새 키워드 추가를 표시한다.
- 표시 용어만 변경하며 내부 `StyleMood` 타입, callable 이름, `styleMoods`·`moodIDs` 데이터 계약은 유지한다.
- 시즌 가져오기는 별도 segment 없이 한 화면에서 위쪽 discovery 상태 카드와 아래쪽 시즌 이미지 import job 목록을 함께 표시한다.
- discovery 요청은 즉시 job receipt를 반환하고, 화면은 브랜드의 최신 job을 Firestore stream으로 관찰한다. 화면 종료는 관찰만 끝내며 서버 job을 취소하지 않는다.
- 상태 카드는 queued/dispatching/running, succeeded, awaitingReview, correctionRequired, failed, cancelled, superseded를 구분하고 각 상태에 맞는 취소·재시도·URL 수정·후보 선택·동일성 검토 진입점만 제공한다. active 본문은 `ProgressView + 주 문구 + 보조 문구` 묶음 전체를 카드 본문 중앙에 두고 취소 action은 하단에 분리한다.
- Phase 3A 구현은 `SeasonImportManagementView.activeDiscoveryContent`와 `discoveryPhaseText`에서 확인한다. 카드 본문 최소 높이 안에서 묶음 전체를 중앙 정렬하며 dispatching/fetching/rendering/parsing/matching/publishing을 사용자 문구로 변환한다.
- `correctionRequired`는 job projection의 issue status를 `개선 대기 중`, `개선 처리 중`, `다시 가져오기 가능`, `추가 작업 필요`로 표시한다. 앱은 issue 목록·fingerprint·fixture·PR·배포 정보를 노출하지 않는다.
- issue 상태 설명은 내부 용어인 `추출 로직/개선된 방식`을 노출하지 않는다. 시즌 목록은 `가져오지 못했어요/다시 가져올 수 있도록 확인하고 있어요/다시 가져올 수 있어요`, 이미지는 같은 어조의 짧은 문구를 사용하며 상태 chip은 기존 값을 유지한다.
- 시즌 목록과 이미지 재시도는 총 관리자에게만 보이며 `fixed`와 상위 동일-stage runtime이 모두 있어야 한다. 앱 ViewModel과 callable 서버가 이 조건을 각각 검사하며 기존 개선 요청 버튼과 동일-version 즉시 재분석 경로는 제거했다.
- 시즌 목록 fix 재시도는 새 discovery job을 만들 때 원본의 서버 검증 fingerprint와 runtime projection을 승계한다. 그래야 contract 2 이상의 실제 성공 job이 cluster를 `verified`로 닫을 수 있다. 2026-08-05 AMOMENTO Development 재시도에서 후보 15개와 해당 전이를 확인했다.
- `wontFix` 중 원본 부재·접근 제한인 시즌 목록 문제는 기존 룩북 목록 URL 수정 action만 제공한다. 상세 구현 기준은 `docs/ai/tasks/lookbook-extraction-issue-operations/`다.
- `awaitingReview` 후보는 `SeasonDiscoveryReviewView`에서 신규 유지, 제외, 기존 시즌 연결 중 하나로 결정한다. 기존 시즌 연결 대상은 시즌명으로 표시하며 job ID는 운영 화면에 노출하지 않는다.
- `awaitingReview`여도 안전하게 `newSeason`으로 분류된 후보는 검토 완료를 기다리지 않고 별도 선택할 수 있다.
- 이미지 import job 행의 기본 식별값은 `SeasonImportJob.displayTitle`이다. `seasonTitle`을 우선하고 `sourceTitle`을 보조로 사용하며 내부 import job ID를 제목으로 표시하지 않는다.
- 신규 시즌 선택 화면은 published snapshot만 읽고, 화면 진입 자체로 discovery를 중복 시작하지 않는다.
- 실제 worker 구조는 `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`를 먼저 본다.

### 삭제 관리 화면

읽기 순서:

1. `Views/Admin/AdminLookbookDeletionManagementView.swift`
2. `ViewModels/AdminLookbookDeletionManagementViewModel.swift`
3. `Domains/Entities/LookbookDeletionRequest.swift`
4. `Repositories/Protocols/LookbookDeletionRepositoryProtocol.swift`
5. `Repositories/Implementations/CloudFunctionsLookbookDeletionRepository.swift`
6. `Repositories/Implementations/CloudFunctionsMappers/LookbookDeletionCloudFunctionsMapper.swift`
7. `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift`
8. `docs/ai/entrypoints/FIREBASE.md`의 삭제 lifecycle

현재 계약:

- 앱 목록은 `active/failed`만 표시한다. 완료/history picker는 없다.
- 총 관리자 전역 목록은 브랜드별로 묶고, 브랜드 관리 내부는 해당 브랜드로 scope한다.
- 총 관리자만 브랜드 삭제 요청/복구와 failed manual retry를 수행한다.
- 브랜드 owner/admin은 해당 브랜드의 시즌·포스트 삭제/복구만 수행한다.
- owner/admin failed 문구는 실행 중/자동 재시도와 최종 실패를 구분한다.
- 다음 page는 목록 전체 하단 sentinel이 요청하며 `requestID`로 중복 제거한다.
- 상세 정책과 검증: `docs/ai/tasks/lookbook-deletion-request-list-simplification/`.

## Domain·Repository 지도

| 영역 | Entity/Store | Repository/UseCase |
| --- | --- | --- |
| 브랜드 | `Brand.swift`, `BrandUserState.swift`, `BrandInteractionStore` | `BrandRepositoryProtocol`, brand use cases |
| 시즌 | `Season.swift`, `SeasonUserState.swift`, `SeasonInteractionStore` | `SeasonRepositoryProtocol`, season use cases |
| 포스트 | `LookbookPost.swift`, `PostUserState.swift`, `PostInteractionStore` | `PostRepositoryProtocol`, post use cases |
| 댓글 | `Comment.swift`, `CommentUserState.swift`, `CommentInteractionStore` | comment repository/use cases |
| 관리자 | `BrandManagement.swift`, `BrandRequest.swift` | brand admin/request repository/use cases |
| 스타일 무드 | `Features/StyleMood/Domain/StyleMood.swift` | read/admin/season mood repository |
| 삭제 | `LookbookDeletionRequest.swift` | `LookbookDeletionRepositoryProtocol` |
| import | `SeasonImportJob.swift`, `SeasonCandidate.swift`, `LookbookExtractionDiagnostic.swift` | import/discovery repositories |
| extraction review | `LookbookExtractionReview.swift` | `LookbookExtractionReviewRepositoryProtocol`, `ManageLookbookExtractionReviewUseCase` |
| existing-season repair | `LookbookSeasonRepair.swift` | `LookbookSeasonRepairRepositoryProtocol`, `ManageLookbookSeasonRepairUseCase` |

- protocol은 `Domains/UseCases`, `Repositories/Protocols`에서 찾는다.
- 댓글 작성자 표시값은 `Domains/Stores/CommentAuthorProfileStore.swift`가 `UserPublicProfile`로 해석한다. 최초·pagination은 누락 작성자만 조회하고, 댓글 목록·답글·포스트 상세의 명시적 refresh는 이미 캐시된 작성자도 강제 재조회한다. 조회 실패는 기존 표시값을 보존하며 `.unknown`을 cache entry로 저장하지 않아 다음 refresh에서 재시도할 수 있다.
- 외부 구현은 `Repositories/Implementations`, DTO는 `Models/DTOs`, 변환은 `Models/Mapper`에서 찾는다.
- 기본 identity가 필요한 DTO mapper는 `documentID`를 명시적으로 받고, Repository가 `DocumentSnapshot.documentID`를 전달한다.
- `SeasonDTO`와 `FirestoreSeasonRepository`는 read-only다. 앱 client create/update는 rules에서 거부하고 기존 시즌 무드는 총 관리자 callable로만 수정한다.
- 상호작용 정합성은 `LookbookInteractionStore`와 대상별 store를 먼저 확인한다.

## 이미지·공유·Navigation

### 이미지

- 2026-09-16 Phase 1: `BrandImageCache` 기존 API → pipeline의 `ImageLoadCoordinator`. 같은 path/maxBytes load의 공용 작업, cache-only 디스크 조회 공유, 소비자별 취소, store/remove/전체 삭제 세대 검사. `LookbookAssetImageView`는 CancellationError/Task 취소에서 다음 후보 요청을 멈추고, BrandRow/InterestedStyleBrandCard/Header도 취소를 일반 실패로 표시하지 않는다. [실제 구현](../tasks/image-loading-stage-concurrency/phase-1-implementation.md). 기존 public protocol/Provider·Container 연결 유지. app/test target compile 통과, 실행·실기기 회귀 미수행. 이전 아래 in-flight 경합 설명은 Phase 0 기준이며 공용 작업 등록은 이번에 보완했다. ViewModel path set/viewport는 Phase 4 대상이다.

- 2026-09-16 Phase 0 계측 코드 적용: `ImageCacheMetrics` → pipeline 단계/세 ViewModel의 metadata·list 공개 → 카드 `ui.*.assigned`/이미지 분기 onAppear. 기존 로딩 정책은 유지한다. [계측 사용법](../tasks/image-loading-stage-concurrency/baseline-instrumentation.md). 앱 build 통과, 실기기 기준선은 미측정이며 아모멘토를 대상으로 준비한다. 아래 계획 미구현 기록 중 Phase 0 상태는 이 기록으로 갱신한다.

- 2026-09-16 단계별 자원 관리 설계·구현 계획: [image-loading-stage-concurrency](../tasks/image-loading-stage-concurrency/implementation-plan.md). 현재는 문서 작성만 완료했고 아래 코드 동작은 아직 변경하지 않았다. 공용 pipeline/외부 URL 캐시 통합과 홈·브랜드 상세·시즌 상세의 데이터 선표시/방향 기반 프리패치를 계획한다.

- 공용 로딩/캐시: `Services/ImageLoading`.
- extraction review와 existing-season repair의 외부 이미지 preview는 `LookbookRemotePreviewImageLoader` 단일 인스턴스를 Container에서 공유한다. 메모리·디스크 캐시, 동일 요청 in-flight 병합, 중복 제거된 8개 window prefetch와 최대 동시 4개 다운로드를 사용한다.
- 공용 렌더링은 `Views/Shared/LookbookRemotePreviewImageView.swift`다. extraction review는 순번·제외 상태가 있는 가로 단일 행 `LazyHStack`, repair는 keep/add/reorder/remove-candidate 구역별 2열 `LazyVGrid`로 표시한다.
- 확대 viewer: `Views/PostDetail/PostImagePreviewView.swift`에 정의된 `LookbookImageViewerView`와 Infra viewer.
- 같은 Storage path 덮어쓰기 시 `updatedAt` 기반 cache invalidation을 확인한다.

시즌 상세 목록 계약:

- `LoadSeasonDetailUseCase`는 source order 포스트를 첫 24개와 `PageCursor`로 반환하고, ViewModel이 cursor를 보존한다.
- 마지막 12개 카드 영역에서 다음 24개를 요청하며 `PostID` 중복 제거, 동일 cursor 동시 호출 차단, refresh generation 이전 결과 폐기를 적용한다.
- Firestore visibility filter로 빈 page가 반환돼도 `nextCursor`가 있으면 다음 page까지 이어서 조회한다.
- 첫 12개와 현재 위치 앞 32개 이미지를 prefetch하고, 다음 page가 append되면 새 이미지 최대 24개를 카드 노출 전에 즉시 큐에 등록한다.
- prefetch concurrency 4는 호출 한 번의 작업 수다. 여러 호출이 겹칠 수 있으므로 공용6 중 visible용2 확보를 보장하지 않는다. 현재 공용 permit은 다운로드뿐 아니라 디코딩·디스크 저장까지 포함한다. 저장은 `.memoryAndDisk`이며 기존 in-flight는 조회/등록이 별도 actor 호출이어서 최초 동시 미스 경합이 가능하다. ViewModel path set은 예약 시 기록하므로 실패·취소·eviction 후 재요청 정책을 보장하지 않는다. 개선 계획은 위 task를 참조한다.
- load-more 실패는 기존 포스트를 유지하고 화면 하단 재시도를 제공한다.

### Chat 공유

- Lookbook 쪽 payload/bridge: `OutPick/Features/Lookbook/`의 share 관련 View/Navigation.
- Chat 접합부: `docs/ai/entrypoints/CHAT.md`.
- snapshot/상세 최신화 결정: ADR-011~013.
- 공유 완료 확인 UI: `Views/Shared/LookbookShareConfirmationBar.swift`와 `BrandDetailView.swift`, `SeasonDetailView.swift`, `PostDetailView.swift`.
- `채팅방으로 이동` 처리 중에는 로딩을 표시하고 이동·계속 보기 버튼과 interactive sheet dismiss를 모두 잠근다. 성공하면 확인 sheet를 닫고, 최신 유효 요청의 실제 실패만 오류 toast와 재시도를 허용한다.

### URL 기반 시즌 import

- 앱: `CreateBrandCandidateSelectionView.swift`, `AdminBrandManagementView.swift`, `SeasonImportManagementView.swift`.
- discovery 상태 owner: `CreateBrandDiscoveryViewModel.swift`. View가 사라질 때는 Firestore 관찰만 끝내고 서버 job은 취소하지 않는다.
- repository: `CloudFunctionsSeasonCandidateDiscoveryRepository.swift`가 최초 `discoveryJobID` 또는 브랜드 published pointer를 관찰하고, `FirestoreSeasonCandidateRepository.swift`가 `newSeason` nested candidate만 로드한다.
- `BrandStoringRepository.createBrand`는 `BrandCreationReceipt(brandID, discoveryJobID)`를 반환해 브랜드 생성 transaction에서 함께 만들어진 최초 job을 그대로 이어받는다.
- 이미지 import 요청은 `discoveryJobID`, `generation`, `candidateSnapshotHash`를 전달한다. 새 discovery generation이 시작되면 브랜드의 published pointer를 같은 transaction에서 즉시 비우며, 서버는 각 import job 생성 또는 asset retry transaction 안에서 브랜드 pointer·job·candidate의 generation/hash, 만료, `newSeason` resolution과 URL을 다시 검증한다.
- review: `LookbookExtractionReviewView.swift`, `LookbookExtractionReviewViewModel.swift`, `CloudFunctionsLookbookExtractionReviewRepository.swift`.
- import 현황의 검토 action은 `LookbookCoordinator`가 상세 화면을 push하고 `LookbookContainer`가 Repository/UseCase/ViewModel을 조립한다.
- review 화면은 예상/발견 수량 방향을 기준으로 동작한다. 초과·예상 수 미확인은 불필요 후보 제외와 `승인`, 미달은 승인 없이 `누락된 이미지 알리기`, content hash 미완료는 승인 차단을 제공한다. correctionRequired 재분석은 총 관리자에게만 노출한다.
- review 초기 로딩 화면은 안내 문구 아래에 accent 색상의 큰 진행 표시를 배치한다.
- 두 review 화면의 외부 후보 이미지는 같은 remote preview loader/cache를 공유하며 URL별 중복 네트워크 요청을 병합한다.
- `원본과 다시 비교` 진행 화면은 설명 아래 accent `ProgressView`를 표시한다. diff가 없으면 상세 화면을 자동 종료하고 목록의 `원본과 다시 비교` 상태로 복귀하며, 실제 변경이 있을 때만 `변경 검토`로 전환한다.
- Functions/worker: `docs/ai/entrypoints/FIREBASE.md`, `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`.
- Cafe24 목록의 `collection_detail.html`처럼 section과 detail을 underscore로 연결한 상세 경로도 공통 discovery 후보로 인정한다. 이미지 링크와 제목 링크가 같은 URL로 분리된 목록은 URL 기준 병합으로 한 시즌 후보에 수렴한다.

## 변경 시 함께 갱신할 문서

- 화면·DI·Coordinator 위치: 이 문서와 `docs/ai/ENTRYPOINTS.md`.
- 데이터/API: `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/FIREBASE.md`.
- 장기 선택: 새 ADR 또는 기존 ADR.
- phase 상태와 QA: 관련 task의 `progress.md`, `qa-checklist.md`.
