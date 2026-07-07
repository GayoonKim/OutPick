# Lookbook Entrypoints

## 공통 구조

- CompositionRoot: `OutPick/Features/Lookbook/LookbookCompositionRoot.swift`
- Container: `OutPick/Features/Lookbook/LookbookContainer.swift`
- Coordinator: `OutPick/Features/Lookbook/Coordinators/LookbookCoordinator.swift`
- Comment coordinator: `OutPick/Features/Lookbook/Coordinators/PostCommentCoordinator.swift`
- ViewModels: `OutPick/Features/Lookbook/ViewModels`
- Views: `OutPick/Features/Lookbook/Views`
- UseCases: `OutPick/Features/Lookbook/Domains/UseCases`
- Entities: `OutPick/Features/Lookbook/Domains/Entities`
- Repository protocols: `OutPick/Features/Lookbook/Repositories/Protocols`
- Repository implementations: `OutPick/Features/Lookbook/Repositories/Implementations`
- Repository provider: `OutPick/Features/Lookbook/Repositories/LookbookRepositoryProvider.swift`
- Environment: `OutPick/Features/Lookbook/Environment`
- Shared stores: `OutPick/Features/Lookbook/Domains/Stores`
- DTO/Firestore mapping: `OutPick/Features/Lookbook/Models`
- Media/image services: `OutPick/Features/Lookbook/Services`
- Navigation helpers: `OutPick/Features/Lookbook/Navigation`

## 조립과 환경

- Lookbook composition root: `OutPick/Features/Lookbook/LookbookCompositionRoot.swift`
  - Lookbook feature root를 앱 탭에 연결하는 조립 진입점이다.
  - Lookbook/Liked root는 `UINavigationController(root: UIHostingController)` 구조이며, UIKit navigation bar는 숨김 유지한다.
  - root nav 생성 뒤 `LookbookCoordinator.attach(navigationController:)`로 Coordinator가 같은 UIKit stack을 소유한다.
- Lookbook container: `OutPick/Features/Lookbook/LookbookContainer.swift`
  - Lookbook repository/use case/store/view model factory를 확인한다.
  - Chat 공유 sheet, current user provider adapter, avatar manager 접합부를 볼 때도 확인한다.
  - avatar manager는 production 기본값을 만들지 않고 앱 세션 조립부에서 명시 주입받는다.
  - 댓글/답글 sheet에서 Profile 상세로 들어갈 때도 `CurrentUserProviding`을 함께 전달한다.
- Lookbook coordinator: `OutPick/Features/Lookbook/Coordinators/LookbookCoordinator.swift`
  - 홈, 브랜드 상세, 시즌 상세, 포스트 상세, 댓글, 공유 sheet navigation을 확인한다.
  - navigation-swipe-back 작업 이후 브랜드/시즌/포스트 상세는 SwiftUI `NavigationLink`가 아니라 Coordinator가 `UIHostingController`를 만들어 UIKit nav stack에 push한다.
  - 상세 화면 커스텀 back은 SwiftUI `dismiss()`가 아니라 Coordinator `pop()`을 호출한다.
  - 상세 Hosting에는 `repositoryProvider` environment와 `BrandAdminSessionStore` environmentObject를 Coordinator가 다시 주입한다.
- Comment coordinator: `OutPick/Features/Lookbook/Coordinators/PostCommentCoordinator.swift`
  - 댓글/답글 sheet, 신고/차단/삭제 action presentation을 확인한다.
- Current user provider: `OutPick/Features/Lookbook/Environment/CurrentUserIDProvider.swift`
  - Lookbook 내부 `UserID?` current user adapter 계약을 확인한다.
- Provider environment: `OutPick/Features/Lookbook/Environment/Provider+Environment.swift`
  - SwiftUI environment 주입을 확인한다.

## 자주 쓰는 Lookbook 흐름

- 홈: `Views/LookbookHome`, `ViewModels/LookbookHomeViewModel.swift`
- 브랜드 상세: `Views/BrandDetail`, `ViewModels/BrandDetailViewModel.swift`
- 시즌 상세: `Views/SeasonDetail`, `ViewModels/SeasonDetailViewModel.swift`
- 포스트 상세/댓글: `Views/PostDetail`, `ViewModels/PostDetailViewModel.swift`, `ViewModels/PostCommentsViewModel.swift`
- 좋아요 탭: `Views/Liked`, `ViewModels/LikedViewModel.swift`
- 브랜드/시즌 생성: `Views/CreateBrand`, `ViewModels/CreateBrandViewModel.swift`, `ViewModels/CreateSeasonViewModel.swift`

## 화면별 주요 파일

- Lookbook home:
  - `OutPick/Features/Lookbook/Views/LookbookHome/LookbookHomeView.swift`
    - root 화면이며 상세 이동은 `NavigationView`/hidden `NavigationLink` route state가 아니라 Coordinator action을 호출한다.
    - 브랜드 생성 fullScreenCover 내부 `NavigationView`는 modal 내부 흐름으로 유지한다.
    - 브랜드 검색 UI와 내 브랜드 요청 진입점을 제공한다.
  - `OutPick/Features/Lookbook/Views/LookbookHome/BrandRowView.swift`
  - `OutPick/Features/Lookbook/ViewModels/LookbookHomeViewModel.swift`
    - 기존 홈 pagination 상태와 callable 기반 브랜드 검색 상태를 분리한다.
- Brand request:
  - `OutPick/Features/Lookbook/Views/BrandRequest/BrandRequestView.swift`
  - `OutPick/Features/Lookbook/Views/BrandRequest/MyBrandRequestsView.swift`
  - `OutPick/Features/Lookbook/ViewModels/BrandRequestViewModel.swift`
  - `OutPick/Features/Lookbook/ViewModels/MyBrandRequestsViewModel.swift`
  - `OutPick/Features/Lookbook/Domains/UseCases/SearchBrandsUseCase.swift`
  - `OutPick/Features/Lookbook/Domains/UseCases/SubmitBrandRequestUseCase.swift`
  - `OutPick/Features/Lookbook/Domains/UseCases/ListMyBrandRequestsUseCase.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsBrandSearchRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsBrandRequestRepository.swift`
- Admin:
  - `OutPick/Features/Lookbook/Views/Admin/LookbookAdminHomeView.swift`
    - Lookbook 관리 홈이며 `요청 목록`, `브랜드 추가`, `브랜드 관리` 메뉴를 제공한다.
    - 총 관리자는 요청 목록/브랜드 추가/브랜드 관리를 모두 볼 수 있고, 브랜드별 owner/admin은 브랜드 관리 중심으로 진입한다.
    - 홈 진입은 `LookbookHomeView`의 `Lookbook 관리` 버튼에서 Coordinator push로 연결한다.
    - 브랜드 생성은 기존 `CreateBrandFlowView`를 fullScreenCover로 재사용한다.
  - `OutPick/Features/Lookbook/Views/Admin/AdminBrandRequestGroupsView.swift`
    - 브랜드 요청 group 목록, 상태 변경, processing group의 브랜드 생성/완료 처리를 담당한다.
    - 처리 시작/검수 후 완료 확인은 중앙 작은 확인창으로 표시하고, 요청 보류 UI는 `룩북 확인 불가`, `스팸`, `기타` 사유 선택 sheet로 표시한다. `기타` 선택 시 admin note를 입력해 `updateBrandRequestGroupStage`로 전달한다.
    - processing group의 브랜드 생성과 완료 처리는 분리한다. 브랜드 생성 직후 자동 완료하지 않고 `markBrandRequestGroupBrandCreated`로 `createdBrandID`를 저장한 뒤, 시즌 import/작업 검수 후 관리자가 `검수 후 완료 처리`를 눌러 `resolveBrandRequestGroup`을 호출한다. 처리중 row는 `상태 변경` 메뉴를 유지하고, `createdBrandID`가 있으면 앱 재실행 후에도 메뉴 안에 `브랜드 생성` 대신 `검수 후 완료 처리`를 보여준다.
  - `OutPick/Features/Lookbook/ViewModels/AdminBrandRequestGroupsViewModel.swift`
    - 요청 group 상태 변경, 보류 사유/rejection reason, admin note 전달을 담당한다.
  - `OutPick/Features/Lookbook/Views/Admin/AdminBrandManagementView.swift`
    - `searchBrands`로 대상 브랜드를 검색/선택한 뒤 브랜드 수정, 로고 업로드, 관리자 추가/삭제, 시즌 추가, 가져오기 현황 진입을 제공한다.
    - 검색 기반 진입에서는 검색어를 지우면 선택 브랜드와 수정 draft를 초기화한다.
    - 브랜드 상세에서 직접 진입한 경우에는 검색 없이 `initialBrand`로 수정 패널을 즉시 seed한다.
  - `OutPick/Features/Lookbook/ViewModels/AdminBrandManagementViewModel.swift`
    - 브랜드 정보 저장 dirty-state, 로고 저장, 관리자 추가/삭제, 결과 피드백 자동 dismiss를 담당한다.
    - 성공/중복/삭제 대상 없음 등 작업 결과 메시지는 짧게 자동 dismiss하고, 실패 메시지는 더 길게 자동 dismiss한다. 입력 검증 오류는 사용자가 수정할 수 있도록 유지한다.
    - 로고 저장은 같은 Storage path를 덮어쓰므로 저장 직후 `BrandImageCache.storeImageData`로 새 thumb/detail 데이터를 캐시에 반영하고 `onBrandUpdated`로 홈/상세 화면의 Brand state를 갱신한다.
  - `OutPick/Features/Lookbook/Domains/Entities/BrandManagement.swift`
- Brand detail:
  - `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailView.swift`
    - 커스텀 back은 Coordinator `pop()`을 호출한다.
    - 관리자 버튼은 서버 재조회 없이 현재 상세 화면이 가진 `Brand`를 `initialBrand`로 `AdminBrandManagementView`에 전달한다.
    - 관리자 화면에서 브랜드 정보/로고가 수정되면 `onUpdatedBrand` 콜백으로 상세 화면의 local `Brand` state를 갱신한다.
  - `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailHeaderView.swift`
    - brand header image tap 확대는 공용 image viewer wrapper인 `LookbookImageViewerView`를 사용한다.
    - 로고 이미지는 같은 Storage path가 덮어써질 수 있으므로 `brand.updatedAt`을 load key에 포함해 path가 같아도 새 이미지로 다시 로드한다.
  - `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailSeasonsGridView.swift`
    - 시즌 탭은 hidden `NavigationLink`가 아니라 Coordinator `pushSeasonDetail`을 호출한다.
  - `OutPick/Features/Lookbook/ViewModels/BrandDetailViewModel.swift`
- Season detail:
  - `OutPick/Features/Lookbook/Views/SeasonDetail/SeasonDetailView.swift`
    - 포스트 탭은 hidden `NavigationLink`가 아니라 Coordinator `pushPostDetail`을 호출한다.
    - 커스텀 back은 Coordinator `pop()`을 호출한다.
  - `OutPick/Features/Lookbook/Views/SeasonDetail/SeasonDetailHeaderCardView.swift`
  - `OutPick/Features/Lookbook/Views/SeasonDetail/SeasonLookGridItemView.swift`
  - `OutPick/Features/Lookbook/ViewModels/SeasonDetailViewModel.swift`
- Post detail/comments:
  - `OutPick/Features/Lookbook/Views/PostDetail/PostDetailView.swift`
    - 커스텀 back은 Coordinator `pop()`을 호출한다.
  - `OutPick/Features/Lookbook/Views/PostDetail/PostImagePreviewView.swift`
    - post hero image 확대와 `LookbookImageViewerView` UIKit wrapper를 확인한다.
    - 1차 구현은 첫 번째 hero image만 열고, storage original 실패 시 remote URL fallback은 wrapper의 load provider 안에서 처리한다.
  - `OutPick/Features/Lookbook/Views/PostDetail/PostCommentsSheetView.swift`
  - `OutPick/Features/Lookbook/Views/PostDetail/PostCommentCardView.swift`
  - `OutPick/Features/Lookbook/Views/PostDetail/PostCommentCardActions.swift`
  - `OutPick/Features/Lookbook/Views/PostDetail/PostCommentRepliesSheetView.swift`
  - `OutPick/Features/Lookbook/Views/PostDetail/CommentUserProfileDetailView.swift`
  - `OutPick/Features/Lookbook/ViewModels/PostDetailViewModel.swift`
  - `OutPick/Features/Lookbook/ViewModels/PostCommentsViewModel.swift`
  - `OutPick/Features/Lookbook/ViewModels/PostCommentRepliesViewModel.swift`
- Liked tab:
  - `OutPick/Features/Lookbook/Views/Liked/LikedView.swift`
    - root 화면이며 좋아요 브랜드/시즌/포스트 상세 이동은 Coordinator push action을 호출한다.
  - `OutPick/Features/Lookbook/ViewModels/LikedViewModel.swift`
- Create brand/season:
  - `OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandFlowView.swift`
  - `OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandView.swift`
    - 브랜드 생성은 브랜드명과 선택 영문 브랜드명을 함께 입력한다. 브랜드 요청 group에서 진입하면 요청의 한글명/영문명이 초기값으로 들어간다.
  - `OutPick/Features/Lookbook/Views/CreateBrand/season/CreateSeasonView.swift`
  - `OutPick/Features/Lookbook/Views/CreateBrand/season/CreateSeasonFromURLView.swift`
  - `OutPick/Features/Lookbook/ViewModels/CreateBrandViewModel.swift`
  - `OutPick/Features/Lookbook/ViewModels/CreateSeasonViewModel.swift`
  - `OutPick/Features/Lookbook/ViewModels/CreateSeasonFromURLViewModel.swift`
- Shared views:
  - `OutPick/Features/Lookbook/Views/Shared/LookbookAssetImageView.swift`
  - `OutPick/Features/Lookbook/Views/Shared/LookbookShareSheetView.swift`
  - `OutPick/Features/Lookbook/Views/Shared/LookbookShareSheetPresentation.swift`
  - `OutPick/Features/Lookbook/Views/Shared/LookbookSharePreviewView.swift`

## Domain stores and interaction state

- Interaction root store: `OutPick/Features/Lookbook/Domains/Stores/LookbookInteractionStore.swift`
  - brand/post/season/comment optimistic interaction store root를 확인한다.
- Brand/Post/Season/Comment stores:
  - `OutPick/Features/Lookbook/Domains/Stores/BrandInteractionStore.swift`
  - `OutPick/Features/Lookbook/Domains/Stores/PostInteractionStore.swift`
  - `OutPick/Features/Lookbook/Domains/Stores/SeasonInteractionStore.swift`
  - `OutPick/Features/Lookbook/Domains/Stores/CommentInteractionStore.swift`
- Pin/cache helpers:
  - `OutPick/Features/Lookbook/Domains/Stores/PinAwareInteractionCache.swift`
  - `OutPick/Features/Lookbook/Domains/Stores/InteractionPinScope.swift`
- Comment author profile store: `OutPick/Features/Lookbook/Domains/Stores/CommentAuthorProfileStore.swift`
- Debug failure injection: `OutPick/Features/Lookbook/Domains/Stores/LookbookDebugFailureInjectionStore.swift`

## Repository layer

- Repository provider: `OutPick/Features/Lookbook/Repositories/LookbookRepositoryProvider.swift`
  - Lookbook repository 묶음 조립을 확인한다.
- Firestore repositories:
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestoreBrandRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestoreSeasonRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestorePostRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestoreCommentRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestoreReplacementRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestoreTagRepository.swift`
- User state repositories:
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestoreBrandUserStateRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestoreSeasonUserStateRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestorePostUserStateRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/FirestoreCommentUserStateRepository.swift`
- Cloud Functions repositories:
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsBrandStore.swift`
    - 브랜드 생성, 브랜드 수정, 로고 경로 반영, 브랜드 관리자 추가/삭제 callable을 감싼다.
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsBrandEngagementRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsSeasonEngagementRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsPostEngagementRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsCommentEngagementRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsCommentWritingRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsCommentSafetyRepository.swift`
  - `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsUserBlockRepository.swift`
- Storage service: `OutPick/Features/Lookbook/Repositories/Implementations/LookbookStorageService.swift`
- UI test fixture provider: `OutPick/Features/Lookbook/Repositories/Implementations/LookbookUITestFixtureRepositoryProvider.swift`

## DTO / Mapping

- DTOs: `OutPick/Features/Lookbook/Models/DTOs`
  - Firestore payload 구조를 확인한다.
- Firestore mapper: `OutPick/Features/Lookbook/Models/Mapping/FirestoreMapper.swift`
  - DTO와 domain entity 변환을 확인한다.
- Mapping error: `OutPick/Features/Lookbook/Models/Mapping/MappingError.swift`

## Image services

- Brand image cache: `OutPick/Features/Lookbook/Services/ImageLoading/BrandImageCache.swift`
- Brand image cache protocol: `OutPick/Features/Lookbook/Services/ImageLoading/BrandImageCacheProtocol.swift`
  - 같은 Storage path를 덮어쓰는 로고 수정 경로에서는 `storeImageData(_:path:)`로 메모리/디스크 캐시를 즉시 교체한다.
- Image thumbnailing protocol: `OutPick/Features/Lookbook/Services/ImageProcessing/Protocols/ImageThumbnailing.swift`
- ImageIO thumbnailer: `OutPick/Features/Lookbook/Services/ImageProcessing/Implementations/ImageIOThumbnailer.swift`
- Thumbnail policies/defaults:
  - `OutPick/Features/Lookbook/Services/ImageProcessing/ThumbnailPolicy.swift`
  - `OutPick/Features/Lookbook/Services/ImageProcessing/ThumbnailPolicies.swift`
  - `OutPick/Features/Lookbook/Services/ImageProcessing/ThumbnailDefaults.swift`

## URL 기반 시즌 import 앱 진입점

- 앱 브랜드/시즌 생성 화면: `OutPick/Features/Lookbook/Views/CreateBrand`
- 앱 생성 ViewModel: `OutPick/Features/Lookbook/ViewModels/CreateBrandViewModel.swift`, `OutPick/Features/Lookbook/ViewModels/CreateSeasonViewModel.swift`
- 시즌 import 시작 UseCase: `OutPick/Features/Lookbook/Domains/UseCases/StartSeasonImportExtractionUseCase.swift`
- import 관리자 화면: `OutPick/Features/Lookbook/Views/BrandDetail/SeasonImportManagementView.swift`
- import 관리자 ViewModel/UseCase: `OutPick/Features/Lookbook/ViewModels/SeasonImportManagementViewModel.swift`, `OutPick/Features/Lookbook/Domains/UseCases/ManageSeasonImportJobsUseCase.swift`
- 실패 asset 재시도 Repository: `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsSeasonAssetRetryRepository.swift`
- Cloud Run worker 아키텍처: `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`

## 브랜드 요청 API 진입점

- Functions: `functions/src/index.ts`
- callable:
  - `searchBrands`
  - `submitBrandRequest`
  - `listMyBrandRequests`
  - `listBrandRequests`
  - `updateBrandRequestStage`
  - `resolveBrandRequest`
  - `listBrandRequestGroups`
  - `updateBrandRequestGroupStage`
  - `resolveBrandRequestGroup`
  - `updateBrand`
  - `addBrandManager`
  - `removeBrandManager`
- 데이터:
  - `brandRequests/{requestID}`
  - `brandRequestNameIndex/{dedupeKeyHash}`
  - `brandRequestDailyCounters/{uid}/brandRequestDays/{yyyyMMdd}`
  - `brandRequestUserLimits/{uid}`
- Phase 2는 백엔드 계약만 구현한다.
- Phase 3에서 Lookbook 홈 검색 결과 없음 CTA, 브랜드 요청 화면, Swift Repository/UseCase/CloudFunctionsManager wrapper를 연결한다.
- Phase 5B iOS 관리자 요청 group 화면:
  - `OutPick/Features/Lookbook/Views/Admin/AdminBrandRequestGroupsView.swift`
  - `OutPick/Features/Lookbook/ViewModels/AdminBrandRequestGroupsViewModel.swift`
  - `OutPick/Features/Lookbook/Domains/UseCases/ListBrandRequestGroupsUseCase.swift`
  - `OutPick/Features/Lookbook/Domains/UseCases/UpdateBrandRequestGroupStageUseCase.swift`
  - `OutPick/Features/Lookbook/Domains/UseCases/ResolveBrandRequestGroupUseCase.swift`
  - `OutPick/Features/Lookbook/Repositories/Protocols/BrandRequestRepositoryProtocol.swift`
  - 상태 변경 메뉴, 처리 시작/검수 후 완료 확인창, 보류 사유 선택 UI는 `AdminBrandRequestGroupsView.swift`를 먼저 확인한다.
- Phase 6A는 processing group에서 기존 `CreateBrandFlowView`를 재사용해 브랜드를 생성한다. 생성 직후 `markBrandRequestGroupBrandCreated`로 `createdBrandID`를 저장하고, 완료 처리는 자동 호출하지 않고 시즌 import/작업 검수 후 `검수 후 완료 처리`로 `resolveBrandRequestGroup`을 호출한다.
- Phase 6B는 `AdminBrandManagementView`에서 브랜드 검색/선택 후 브랜드 수정, 로고 수정, 관리자 추가/삭제, 시즌 추가/import 현황 진입을 제공한다.
- Phase 6H QA 수정은 `AdminBrandManagementViewModel`, `BrandDetailView`, `BrandDetailHeaderView`, `BrandRowView`, `BrandImageCache`를 함께 확인한다. 특히 상세에서 직접 관리자 진입은 `initialBrand` seed, 로고 수정 반영은 cache store + `updatedAt` load key가 핵심이다.
- Phase 7 iOS 관리자 시즌 import QA는 `SeasonAdditionSheetView`, `SeasonImportManagementView`, `SeasonImportManagementViewModel`, `ManageSeasonImportJobsUseCase`와 `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`를 함께 확인한다.
- 사용자별 `brandRequests/{requestID}`는 개인 요청 기록이며, 사용자 노출 상태는 `listMyBrandRequests`가 group 상태를 반영해 반환한다.
