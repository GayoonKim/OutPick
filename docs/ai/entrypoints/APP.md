# App Entrypoints

## Development/Production 빌드 환경

- 공유 scheme: `OutPick.xcodeproj/xcshareddata/xcschemes/OutPick-{Development,Production}.xcscheme`.
- Build Configuration: `Development-Debug`, `Development-Release`, `Production-Debug`, `Production-Release`.
- 공통·환경별 설정: `Configurations/Base.xcconfig`, `Configurations/Development.xcconfig`, `Configurations/Production.xcconfig`.
- 앱 번들 환경값: `OutPick/Info.plist`의 `OUTPICK_ENVIRONMENT`, `OUTPICK_EXPECTED_FIREBASE_PROJECT_ID`, `OUTPICK_SOCKET_URL`, Google/Kakao callback 설정.
- runtime source of truth: `OutPick/App/Firebase/AppRuntimeConfiguration.swift`가 Bundle ID, Firebase project, Socket URL, Google callback, Kakao Native App Key와 callback scheme의 환경 정합성을 검증한다.
- Firebase bootstrap: `OutPick/App/AppDelegate.swift`가 선택된 plist를 명시적으로 읽고 runtime 정합성 확인 후 `FirebaseApp.configure(options:)`를 호출한다.
- Firebase build gate: `scripts/build/validate-and-copy-firebase-config.sh`가 로컬 plist의 존재 여부와 Bundle ID/Firebase project/Google callback/Socket 조합을 검증한 뒤 앱 번들에 `GoogleService-Info.plist`로 복사한다.
- 실제 plist는 `LocalSecrets/Firebase/{Development,Production}/GoogleService-Info.plist`에 두며 Git에 커밋하지 않는다.
- Development는 `GayoonKim.OutPick.dev`·`OutPick DEV`·`outpick-test`, Production은 `GayoonKim.OutPick`·`OutPick`·`outpick-664ae`가 고정 계약이다.
- Google/Kakao callback은 환경별 xcconfig로 분리한다. Development Kakao Native App Key는 `f5f18b00bc7b163aa5be39fef99e646d`, Production은 기존 키 `a2b20f7bedfb9582147f572ef004d0f0`을 사용하며 URL scheme은 각 키에서 파생된다.
- Development Socket은 `outpick-test`의 Cloud Run `outpick-socket-development` canonical URL을 사용한다. Production Socket URL과 같아지거나 누락되면 build/runtime에서 실패한다.
- iOS Socket 선택 진입점은 `RealtimeSocketService.makeSocketURL()`이며 하드코딩 운영 URL이 아니라 검증된 `AppRuntimeConfiguration.socketURL`만 사용한다.

## 앱 조립과 탭

- AppCompositionRoot: `OutPick/App/AppCompositionRoot.swift`
  - 앱 세션 dependency graph 조립 진입점이다.
  - `AppDatabase.live` factory를 가장 먼저 실행하고 실패를 `AppBootstrapError`로 변환한다.
  - `RealtimeSocketService`, `JoinedRoomsSessionStore`, `BrandAdminSessionStore`, `CurrentUserSessionStore`, `CurrentUserProviding`, `AppSessionRuntime`, `AppCoordinator`를 같은 앱 graph에서 만든다.
  - 앱 세션 단위 `AvatarImageService`도 여기서 생성해 Chat/Lookbook/Profile로 전달한다.
- AppCoordinator: `OutPick/App/AppCoordinator.swift`
  - 로그인 여부 확인, 로그인/프로필/메인 탭 루트 전환, 강제 로그아웃 라우팅을 담당한다.
  - Lookbook/Chat Container를 메인 탭 수명 동안 유지한다.
  - 인증 세션 runtime 시작/정지, 같은 realtime service 주입, 같은 avatar manager 주입 흐름을 연결한다.
- SceneDelegate: `OutPick/App/SceneDelegate.swift`
  - UIWindow 생성, throwable AppCoordinator 생성, Kakao/Google URL callback, notification route 전달을 담당한다.
  - DB bootstrap 실패 시 성공하지 않은 Coordinator는 보관하지 않고 독립 실패 화면을 root로 표시하며 수동 재시도를 연결한다.
  - 알림 launch route는 bootstrap보다 먼저 저장한다.
  - Scene lifecycle presence는 AppCoordinator를 거쳐 AppSessionRuntime으로 위임한다.
- App bootstrap failure: `OutPick/App/Bootstrap/`
  - `AppBootstrapError.swift`: 앱 조립 경계의 로컬 DB 초기화 오류다.
  - `AppBootstrapFailureViewController.swift`: DB에 의존하지 않는 실패 root와 `다시 시도` 동작이다.
  - `AppBootstrapFailureInjector.swift`: DEBUG에서만 `--app-bootstrap-fail-database-once`/`--app-bootstrap-fail-database-always`를 해석한다. 실제 DB 파일을 손상·삭제하지 않는다.
- AppSessionRuntime: `OutPick/App/AppSessionRuntime.swift`
  - 인증 세션의 socket connect/disconnect/reset, joined room join/leave command, banner runtime 시작/정지를 담당한다.
- JoinedRoomsSessionStore: `OutPick/App/Session/JoinedRoomsSessionStore.swift`
  - 앱 세션의 참여중 roomID snapshot store다.
  - `JoinedRoomsStore.swift`의 대체 진입점이며 Combine publisher 없이 명시 command API와 함께 사용한다.
- CurrentUserSessionStore: `OutPick/App/Session/CurrentUserSessionStore.swift`
  - 앱 세션의 current user profile snapshot store다.
  - 로그인/프로필 생성/수정 후 메모리 profile source를 갱신한다.
- CurrentUserProvider: `OutPick/App/Session/CurrentUserProvider.swift`
  - 앱 공통 현재 사용자 조회 계약이다.
  - 현재 사용자 식별자는 Firebase Auth UID 기반 `canonicalUserID` 하나로 노출한다.
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
  - 마이페이지의 일반 사용자 브랜드 요청 내역 진입 시 MyPage 탭 navigation stack에 Lookbook 요청 상황 화면을 push한다.

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
  - 현재 사용자 식별자는 `canonicalUserID`를 사용한다.
- Login bootstrapping: `OutPick/Features/Login/Application/LoginManager+Bootstrapping.swift`
- Auth Repository: `OutPick/Features/Login/Repository/DefaultSocialAuthRepository.swift`
- Protocols: `OutPick/Features/Login/Protocols`

## MyPage

- Root controller: `OutPick/Features/MyPage/Controller/MyPageViewController.swift`
- 탭 진입점: `DefaultMainTabBuilder`의 index 4.
- `EDIT`에는 프로필 편집과 관심 스타일을, `ACTIVITY`에는 일반 사용자 본인의 브랜드 요청 내역을 표시한다.
- 브랜드 요청 내역 route는 `MyPageCoordinator` → `MyPageContainer.appContentRouter` → `DefaultAppContentRouter.openMyBrandRequests()`다.

## Infra

- Alert: `OutPick/Infra/Alert`
- Toast: `OutPick/Infra/Toast`
- Network status: `OutPick/Infra/Network`
- Media processing: `OutPick/Infra/Media`
- Keychain: `OutPick/Infra/Keychain`
- Cache/Image cache: `OutPick/Infra/Cache`
- Shared UI: `OutPick/Infra/ShareView`
- Keyboard dismiss: `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`
  - UIKit 화면은 `installKeyboardDismissTapGesture()`를 view/controller에 적용한다.
  - SwiftUI 화면은 `outpickDismissKeyboardOnTap()` modifier를 root 또는 입력 sheet root에 적용한다.
- Navigation transitions: `OutPick/Infra/Utility/Transitions`
