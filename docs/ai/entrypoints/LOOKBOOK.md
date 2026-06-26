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
- Lookbook container: `OutPick/Features/Lookbook/LookbookContainer.swift`
  - Lookbook repository/use case/store/view model factory를 확인한다.
  - Chat 공유 sheet, current user provider adapter, avatar manager 접합부를 볼 때도 확인한다.
  - avatar manager는 production 기본값을 만들지 않고 앱 세션 조립부에서 명시 주입받는다.
  - 댓글/답글 sheet에서 Profile 상세로 들어갈 때도 `CurrentUserProviding`을 함께 전달한다.
- Lookbook coordinator: `OutPick/Features/Lookbook/Coordinators/LookbookCoordinator.swift`
  - 홈, 브랜드 상세, 시즌 상세, 포스트 상세, 댓글, 공유 sheet navigation을 확인한다.
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
  - `OutPick/Features/Lookbook/Views/LookbookHome/BrandRowView.swift`
  - `OutPick/Features/Lookbook/ViewModels/LookbookHomeViewModel.swift`
- Brand detail:
  - `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailView.swift`
  - `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailHeaderView.swift`
    - brand header image tap 확대는 공용 image viewer wrapper인 `LookbookImageViewerView`를 사용한다.
  - `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailSeasonsGridView.swift`
  - `OutPick/Features/Lookbook/ViewModels/BrandDetailViewModel.swift`
- Season detail:
  - `OutPick/Features/Lookbook/Views/SeasonDetail/SeasonDetailView.swift`
  - `OutPick/Features/Lookbook/Views/SeasonDetail/SeasonDetailHeaderCardView.swift`
  - `OutPick/Features/Lookbook/Views/SeasonDetail/SeasonLookGridItemView.swift`
  - `OutPick/Features/Lookbook/ViewModels/SeasonDetailViewModel.swift`
- Post detail/comments:
  - `OutPick/Features/Lookbook/Views/PostDetail/PostDetailView.swift`
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
  - `OutPick/Features/Lookbook/ViewModels/LikedViewModel.swift`
- Create brand/season:
  - `OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandFlowView.swift`
  - `OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandView.swift`
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
