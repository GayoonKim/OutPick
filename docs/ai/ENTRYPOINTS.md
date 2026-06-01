# OutPick Entrypoints

## 목적

기능 수정이나 새 기능 추가 시 AI 에이전트가 어디부터 봐야 하는지 빠르게 확인하기 위한 문서다.

## 공통 진입점

- 앱 시작/루트 라우팅: `OutPick/App/AppCoordinator.swift`
- Scene 연결/초기 DI: `OutPick/App/SceneDelegate.swift`
- 탭 조립: `OutPick/App/TabBarController/Composition`
- 탭 화면: `OutPick/App/TabBarController/MainTab`
- 기능 코드: `OutPick/Features`
- 공통 인프라: `OutPick/Infra`
- Firebase Functions: `functions/src/index.ts`
- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`
- 단위 테스트: `OutPickTests`
- UI 테스트: `OutPickUITests`

## 앱 조립과 탭

- AppCoordinator: `OutPick/App/AppCoordinator.swift`
  - 로그인 여부 확인, 로그인/프로필/메인 탭 루트 전환, 강제 로그아웃 라우팅을 담당한다.
  - Lookbook/Chat Container를 메인 탭 수명 동안 유지한다.
- SceneDelegate: `OutPick/App/SceneDelegate.swift`
  - UIWindow 생성, AppCoordinator 생성, Kakao/Google URL callback, notification route 전달을 담당한다.
- MainTabCompositionRoot: `OutPick/App/TabBarController/Composition/MainTabCompositionRoot.swift`
  - CustomTabBarViewController 조립 진입점이다.
- DefaultMainTabBuilder: `OutPick/App/TabBarController/Composition/DefaultMainTabBuilder.swift`
  - 탭 index별 root ViewController를 생성한다.
  - 현재 탭 순서: 채팅 목록, 참여 채팅방, 룩북, 좋아요, 마이페이지.

## Lookbook

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

자주 쓰는 Lookbook 흐름:

- 홈: `Views/LookbookHome`, `ViewModels/LookbookHomeViewModel.swift`
- 브랜드 상세: `Views/BrandDetail`, `ViewModels/BrandDetailViewModel.swift`
- 시즌 상세: `Views/SeasonDetail`, `ViewModels/SeasonDetailViewModel.swift`
- 포스트 상세/댓글: `Views/PostDetail`, `ViewModels/PostDetailViewModel.swift`, `ViewModels/PostCommentsViewModel.swift`
- 좋아요 탭: `Views/Liked`, `ViewModels/LikedViewModel.swift`
- 브랜드/시즌 생성: `Views/CreateBrand`, `ViewModels/CreateBrandViewModel.swift`, `ViewModels/CreateSeasonViewModel.swift`

## Chat

- CompositionRoot: `OutPick/Features/Chat/ChatCompositionRoot.swift`
- Container: `OutPick/Features/Chat/ChatContainer.swift`
- Coordinator: `OutPick/Features/Chat/ChatCoordinator.swift`
- ViewModels: `OutPick/Features/Chat/ViewModels`
- Controllers: `OutPick/Features/Chat/Controllers`
- UseCases: `OutPick/Features/Chat/Domain/UseCases`
- Repositories/Managers: `OutPick/Features/Chat/Repositories`, `OutPick/Features/Chat/Managers`
- Domain models: `OutPick/Features/Chat/Domain/Models`
- Image loading services: `OutPick/Features/Chat/Services/ImageLoading`
- Joined rooms store: `OutPick/Features/Chat/Domain/Models/JoinedRoomsStore.swift`

## Profile

- CompositionRoot: `OutPick/Features/Profile/ProfileCompositionRoot.swift`
- Detail CompositionRoot: `OutPick/Features/Profile/UserProfileDetailCompositionRoot.swift`
- Coordinator: `OutPick/Features/Profile/ProfileCoordinator.swift`
- Detail Coordinator: `OutPick/Features/Profile/UserProfileDetailCoordinator.swift`
- ViewModels: `OutPick/Features/Profile/ViewModels`
- Views: `OutPick/Features/Profile/Views`
- Repositories: `OutPick/Features/Profile/Repository`
- Domain: `OutPick/Features/Profile/Domain`
- Firestore mapping: `OutPick/Features/Profile/Mapper`
- DTO: `OutPick/Features/Profile/DTO`

## Login

- CompositionRoot: `OutPick/Features/Login/Presentation/LoginCompositionRoot.swift`
- ViewModel: `OutPick/Features/Login/Presentation/LoginViewModel.swift`
- ViewController: `OutPick/Features/Login/Presentation/LoginViewController.swift`
- Boot loading: `OutPick/Features/Login/Presentation/BootLoadingViewController.swift`
- Login manager: `OutPick/Features/Login/Application/LoginManager.swift`
- Login bootstrapping: `OutPick/Features/Login/Application/LoginManager+Bootstrapping.swift`
- Auth Repository: `OutPick/Features/Login/Repository/DefaultSocialAuthRepository.swift`
- Protocols: `OutPick/Features/Login/Protocols`

## MyPage

- Root controller: `OutPick/Features/MyPage/MyPageController/MyPageViewController.swift`
- 탭 진입점: `DefaultMainTabBuilder`의 index 4.

## Infra

- Alert: `OutPick/Infra/Alert`
- Toast: `OutPick/Infra/Toast`
- Network status: `OutPick/Infra/Network`
- Media processing: `OutPick/Infra/Media`
- Keychain: `OutPick/Infra/Keychain`
- Cache/Image cache: `OutPick/Infra/Cache`
- Shared UI: `OutPick/Infra/ShareView`
- Navigation transitions: `OutPick/Infra/Utility/Transitions`

## Firebase Functions

- Export entry: `functions/src/index.ts`
- Lookbook import worker: `functions/src/lookbookImportWorker.ts`
- Lookbook materializer: `functions/src/lookbookImportMaterializer.ts`
- Lookbook asset sync: `functions/src/lookbookAssetSyncWorker.ts`
- Season candidate discovery: `functions/src/lookbookSeasonCandidateDiscovery.ts`

주요 callable/trigger:

- Auth: `exchangeKakaoToken`
- Brand: `getBrandAdminCapabilities`, `createBrand`, `updateBrandLogoPaths`, `setBrandEngagement`
- Post: `setPostEngagement`
- Season: `setSeasonEngagement`
- Comment: `setCommentEngagement`, `createComment`, `createReply`, `deleteComment`, `reportComment`
- User safety: `blockUser`, `loadHiddenCommentUserIDs`
- Season import: `requestSeasonImport`, `processNextSeasonImportJob`, `processSeasonImportJobs`, `requestSeasonCandidateImportsAndProcess`, `createSeasonContentFromImportJobs`
- Firestore triggers: `onSeasonImportParsed`, `onSeasonImportContentCreated`, `onRoomClosed`

## 테스트

- Lookbook interaction/store tests: `OutPickTests/LookbookInteractionStoreTests.swift`, `OutPickTests/LookbookDebugFailureInjectionStoreTests.swift`
- Lookbook detail tests: `OutPickTests/PostDetailScreenViewModelTests.swift`, `OutPickTests/SeasonDetailViewModelTests.swift`
- 좋아요 탭 tests: `OutPickTests/LikedViewModelTests.swift`, `OutPickTests/LoadLikedSeasonsUseCaseTests.swift`
- UI smoke/failure tests: `OutPickUITests/LookbookSmokeUITests.swift`, `OutPickUITests/LookbookInteractionFailureToastUITests.swift`
- UI test support/robots: `OutPickUITests/LookbookUITestSupport.swift`, `OutPickUITests/LookbookPostDetailRobot.swift`, `OutPickUITests/LookbookCommentsRobot.swift`

## 좋아요 탭 현재 작업

- 진행 문서: `docs/ai/tasks/liked-tab/`
- 현재 상태 포인터: `docs/ai/tasks/active.md`
- 루트 포인터: `HANDOFF.md`
