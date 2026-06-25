# App Entrypoints

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
- Joined rooms session store: `OutPick/App/Session/JoinedRoomsSessionStore.swift`

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
