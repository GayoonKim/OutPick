# Lookbook Entrypoints

## 공통 구조

- CompositionRoot: `OutPick/Features/Lookbook/LookbookCompositionRoot.swift`
- Container: `OutPick/Features/Lookbook/LookbookContainer.swift`
- Coordinator: `OutPick/Features/Lookbook/Coordinators/LookbookCoordinator.swift`
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

## 자주 쓰는 Lookbook 흐름

- 홈: `Views/LookbookHome`, `ViewModels/LookbookHomeViewModel.swift`
- 브랜드 상세: `Views/BrandDetail`, `ViewModels/BrandDetailViewModel.swift`
- 시즌 상세: `Views/SeasonDetail`, `ViewModels/SeasonDetailViewModel.swift`
- 포스트 상세/댓글: `Views/PostDetail`, `ViewModels/PostDetailViewModel.swift`, `ViewModels/PostCommentsViewModel.swift`
- 좋아요 탭: `Views/Liked`, `ViewModels/LikedViewModel.swift`
- 브랜드/시즌 생성: `Views/CreateBrand`, `ViewModels/CreateBrandViewModel.swift`, `ViewModels/CreateSeasonViewModel.swift`

## URL 기반 시즌 import 앱 진입점

- 앱 브랜드/시즌 생성 화면: `OutPick/Features/Lookbook/Views/CreateBrand`
- 앱 생성 ViewModel: `OutPick/Features/Lookbook/ViewModels/CreateBrandViewModel.swift`, `OutPick/Features/Lookbook/ViewModels/CreateSeasonViewModel.swift`
- 시즌 import 시작 UseCase: `OutPick/Features/Lookbook/Domains/UseCases/StartSeasonImportExtractionUseCase.swift`
- import 관리자 화면: `OutPick/Features/Lookbook/Views/BrandDetail/SeasonImportManagementView.swift`
- import 관리자 ViewModel/UseCase: `OutPick/Features/Lookbook/ViewModels/SeasonImportManagementViewModel.swift`, `OutPick/Features/Lookbook/Domains/UseCases/ManageSeasonImportJobsUseCase.swift`
- 실패 asset 재시도 Repository: `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsSeasonAssetRetryRepository.swift`
- Cloud Run worker 아키텍처: `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`
