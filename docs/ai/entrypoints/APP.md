# App Entrypoints

## 앱 조립과 탭

- AppCompositionRoot: `OutPick/App/AppCompositionRoot.swift`
  - 앱 세션 dependency graph 조립 진입점이다.
  - `RealtimeSocketService`, `JoinedRoomsSessionStore`, `BrandAdminSessionStore`, `CurrentUserProviding`, `AppSessionRuntime`, `AppCoordinator`를 같은 앱 graph에서 만든다.
  - 앱 세션 단위 `AvatarImageService`도 여기서 생성해 Chat/Lookbook/Profile로 전달한다.
- AppCoordinator: `OutPick/App/AppCoordinator.swift`
  - 로그인 여부 확인, 로그인/프로필/메인 탭 루트 전환, 강제 로그아웃 라우팅을 담당한다.
  - Lookbook/Chat Container를 메인 탭 수명 동안 유지한다.
  - 인증 세션 runtime 시작/정지, 같은 realtime service 주입, 같은 avatar manager 주입 흐름을 연결한다.
- SceneDelegate: `OutPick/App/SceneDelegate.swift`
  - UIWindow 생성, AppCoordinator 생성, Kakao/Google URL callback, notification route 전달을 담당한다.
  - Scene lifecycle presence는 AppCoordinator를 거쳐 AppSessionRuntime으로 위임한다.
- AppSessionRuntime: `OutPick/App/AppSessionRuntime.swift`
  - 인증 세션의 socket connect/disconnect/reset, joined room join/leave command, banner runtime 시작/정지를 담당한다.
- JoinedRoomsSessionStore: `OutPick/App/Session/JoinedRoomsSessionStore.swift`
  - 앱 세션의 참여중 roomID snapshot store다.
  - `JoinedRoomsStore.swift`의 대체 진입점이며 Combine publisher 없이 명시 command API와 함께 사용한다.
- MainTabCompositionRoot: `OutPick/App/TabBarController/Composition/MainTabCompositionRoot.swift`
  - `MainTabBarController` 조립 진입점이다.
  - `UITabBarController + 각 탭 UINavigationController` 기반 메인 탭 shell을 만든다.
- MainTabBarController: `OutPick/App/TabBarController/MainTab/MainTabBarController.swift`
  - 표준 UIKit tab shell이다.
  - 같은 탭 재선택은 no-op으로 처리한다.
  - selected tab의 active presenter와 navigation controller를 앱 라우터에 제공한다.
- OutPickTabBar: `OutPick/App/TabBarController/MainTab/OutPickTabBar.swift`
  - 54pt 성격의 탭 바 높이를 유지하는 `UITabBar` subclass다.
- DefaultMainTabBuilder: `OutPick/App/TabBarController/Composition/DefaultMainTabBuilder.swift`
  - 탭 index별 root `UINavigationController`와 tab bar item을 생성한다.
  - 현재 탭 순서: 채팅 목록, 참여 채팅방, 룩북, 좋아요, 마이페이지.
- DefaultAppContentRouter: `OutPick/App/Routing/DefaultAppContentRouter.swift`
  - 탭 전환과 cross-feature route를 담당한다.
  - `UITabBarController.selectedIndex`와 selected navigation controller를 기준으로 joined chat room/lookbook shared content route를 연다.

## Chat

- 상세 코드 지도: `docs/ai/entrypoints/CHAT.md`
- CompositionRoot: `OutPick/Features/Chat/ChatCompositionRoot.swift`
- Container: `OutPick/Features/Chat/ChatContainer.swift`
- Coordinator: `OutPick/Features/Chat/ChatCoordinator.swift`
- ViewModels: `OutPick/Features/Chat/ViewModels`
- Controllers: `OutPick/Features/Chat/Controllers`
- UseCases: `OutPick/Features/Chat/Domain/UseCases`
- Repositories/Managers: `OutPick/Features/Chat/Repositories`, `OutPick/Features/Chat/Managers`
- Domain models: `OutPick/Features/Chat/Domain/Models`
- Image loading services: `OutPick/Features/Chat/Services/ImageLoading`
- Joined rooms session store: `OutPick/App/Session/JoinedRoomsSessionStore.swift`
- Realtime socket service: `OutPick/Infra/Realtime/RealtimeSocketService.swift`
- Socket server: `Socket/index.js`, `Socket/src`

## Feature별 상세 코드 지도

- Chat: `docs/ai/entrypoints/CHAT.md`
- Login/Auth: `docs/ai/entrypoints/LOGIN.md`
- Lookbook: `docs/ai/entrypoints/LOOKBOOK.md`
- Profile: `docs/ai/entrypoints/PROFILE.md`
- MyPage: `docs/ai/entrypoints/MYPAGE.md`
- Data/Firebase/GRDB: `docs/ai/entrypoints/DATA.md`
- Infra/shared services: `docs/ai/entrypoints/INFRA.md`

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
