//
//  AppCoordinator.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit
import FirebaseAuth

@MainActor
final class AppCoordinator {
    static weak var activeCoordinator: AppCoordinator?

    private let window: UIWindow
    private weak var currentWindowScene: UIWindowScene?
    private weak var mainTabController: MainTabBarController?

    private let lookbookProvider: LookbookRepositoryProvider
    private var lookbookContainer: LookbookContainer?
    private var chatContainer: ChatContainer?
    private let joinedRoomsStore: JoinedRoomsSessionStore
    private let brandAdminSessionStore: BrandAdminSessionStore
    private let socialAuthRepository: SocialAuthRepositoryProtocol
    private let currentUserSessionStore: CurrentUserSessionStore
    private let currentUserProvider: any CurrentUserProviding
    private let realtimeSocketService: RealtimeSocketService
    private let avatarImageManager: AvatarImageManaging
    private let appSessionRuntime: AppSessionRuntime
    private let chatPersistence: ChatPersistenceProvider
    private var sessionResetTask: Task<Void, Never>?
    
    private var profileCoordinator: ProfileCoordinator?

    // Profile flow DI
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let publicProfileRepository: UserPublicProfileRepositoryProtocol
    private let loadCurrentUserBootstrapUseCase: LoadCurrentUserBootstrapUseCase
    private let styleMoodRepository: StyleMoodRepositoryProtocol
    private let checkNicknameAvailabilityUseCase: CheckNicknameAvailabilityUseCase
    private let completeOnboardingUseCase: CompleteOnboardingUseCase
    private let updatePublicProfileUseCase: UpdatePublicProfileUseCase
    private let updateStylePreferencesUseCase: UpdateStylePreferencesUseCase
    private let accountRepository: CurrentUserAccountRepositoryProtocol

    // 로그인 화면이 이미 떠있는데 또 showLogin()을 타는 걸 막기 위한 플래그
    private var isShowingLogin: Bool = false

    init(
        window: UIWindow,
        lookbookProvider: LookbookRepositoryProvider,
        userProfileRepository: UserProfileRepositoryProtocol,
        publicProfileRepository: UserPublicProfileRepositoryProtocol,
        loadCurrentUserBootstrapUseCase: LoadCurrentUserBootstrapUseCase,
        styleMoodRepository: StyleMoodRepositoryProtocol,
        checkNicknameAvailabilityUseCase: CheckNicknameAvailabilityUseCase,
        completeOnboardingUseCase: CompleteOnboardingUseCase,
        updatePublicProfileUseCase: UpdatePublicProfileUseCase,
        updateStylePreferencesUseCase: UpdateStylePreferencesUseCase,
        accountRepository: CurrentUserAccountRepositoryProtocol,
        joinedRoomsStore: JoinedRoomsSessionStore,
        brandAdminSessionStore: BrandAdminSessionStore,
        socialAuthRepository: SocialAuthRepositoryProtocol,
        currentUserSessionStore: CurrentUserSessionStore,
        currentUserProvider: any CurrentUserProviding,
        realtimeSocketService: RealtimeSocketService,
        avatarImageManager: AvatarImageManaging,
        appSessionRuntime: AppSessionRuntime,
        chatPersistence: ChatPersistenceProvider
    ) {
        self.window = window
        self.lookbookProvider = lookbookProvider
        self.userProfileRepository = userProfileRepository
        self.publicProfileRepository = publicProfileRepository
        self.loadCurrentUserBootstrapUseCase = loadCurrentUserBootstrapUseCase
        self.styleMoodRepository = styleMoodRepository
        self.checkNicknameAvailabilityUseCase = checkNicknameAvailabilityUseCase
        self.completeOnboardingUseCase = completeOnboardingUseCase
        self.updatePublicProfileUseCase = updatePublicProfileUseCase
        self.updateStylePreferencesUseCase = updateStylePreferencesUseCase
        self.accountRepository = accountRepository
        self.joinedRoomsStore = joinedRoomsStore
        self.brandAdminSessionStore = brandAdminSessionStore
        self.socialAuthRepository = socialAuthRepository
        self.currentUserSessionStore = currentUserSessionStore
        self.currentUserProvider = currentUserProvider
        self.realtimeSocketService = realtimeSocketService
        self.avatarImageManager = avatarImageManager
        self.appSessionRuntime = appSessionRuntime
        self.chatPersistence = chatPersistence
        self.window.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        Self.activeCoordinator = self
    }

    @MainActor
    func start(windowScene: UIWindowScene) {
        self.currentWindowScene = windowScene

        // 앱 시작 시 강제 로그아웃 콜백 설치(메인 탭/프로필 플로우에서 사용)
        installForceLogoutHandler()

        setRoot(BootLoadingViewController(), animated: true)

        #if DEBUG
        if routeForUITestAuthenticatedSessionIfNeeded() {
            return
        }
        #endif

        Task { [weak self] in
            guard let self else { return }

            let ok = await LoginManager.shared.checkExistingLogin()
            if ok {
                await self.routeAfterAuthenticated()
            } else {
                await MainActor.run { self.showLogin(windowScene: windowScene) }
            }
        }
    }

    private func installForceLogoutHandler() {
        // 강제 로그아웃 이벤트는 콜백으로 수신해 루트 라우팅을 변경
        LoginManager.shared.onForceLogout = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                // 이미 로그인 화면이면 중복 라우팅 방지
                if self.isShowingLogin { return }

                guard let scene = self.window.windowScene ?? self.currentWindowScene else { return }
                self.showLogin(windowScene: scene)
            }
        }
    }

    private func routeAfterAuthenticated() async {
        print("[AppCoordinator] routeAfterAuthenticated identity=\(LoginManager.shared.canonicalUserID)")
        sessionResetTask?.cancel()
        sessionResetTask = nil
        await MainActor.run { self.setRoot(BootLoadingViewController(), animated: false) }

        do {
            let userID = try await LoginManager.shared.ensureUserDocumentID()
            let outcome = try await loadCurrentUserBootstrapUseCase.execute(userID: userID)

            switch outcome {
            case .ready(_, let publicProfile):
            print("[AppCoordinator] complete profile found. Showing main tab.")
            await MainActor.run {
                self.currentUserSessionStore.replaceProfile(publicProfile)
                _ = self.ensureChatContainer()
                self.prewarmLookbookHome()
            }

            // 새 기기 로그인 = 기존 기기 로그아웃 정책 시작점
            do {
                try await LoginManager.shared.updateLogDevID()
            }
            catch {
                print("updateLogDevID 실패: \(error)")
            }

            do {
                try await LoginManager.shared.bootstrapAfterLogin(
                    joinedRoomsStore: joinedRoomsStore,
                    joinedRoomsRuntime: appSessionRuntime,
                    brandAdminSessionStore: brandAdminSessionStore
                )
            } catch {
                print("bootstrapAfterLogin 실패: \(error)")
            }

            await MainActor.run { self.showMainTab() }

            case .needsOnboarding:
                print("[AppCoordinator] account is missing/incomplete. Showing onboarding.")
                await MainActor.run { self.showProfileFlow(userID: userID) }

            case .deletionPending:
                print("[AppCoordinator] account deletion is pending.")
                await MainActor.run { self.showDeletionPending() }
            }
        } catch {
            print("[AppCoordinator] bootstrap failed. error=\(error)")
            await MainActor.run { self.showAuthenticatedBootstrapFailure() }
        }
    }

    @MainActor
    func routeToLoginAfterLogout() {
        guard let scene = window.windowScene ?? currentWindowScene else { return }
        showLogin(windowScene: scene)
    }

    @MainActor
    func handleLoginSuccess(_ authenticatedUser: AuthenticatedUser) {
        LoginManager.shared.setAuthenticatedUser(authenticatedUser)
        Task { [weak self] in
            guard let self else { return }
            await self.routeAfterAuthenticated()
        }
    }

    // MARK: - 화면 전환

    @MainActor
    private func showLogin(windowScene: UIWindowScene) {
        self.joinedRoomsStore.clear()
        self.appSessionRuntime.clearJoinedRooms()
        self.currentUserSessionStore.clear()

        sessionResetTask?.cancel()
        sessionResetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.appSessionRuntime.stopAuthenticatedSession()
        }

        self.profileCoordinator = nil
        self.lookbookContainer = nil
        self.chatContainer = nil
        self.mainTabController = nil
        self.brandAdminSessionStore.reset()
        // 로그인 화면으로 들어갈 땐 강제로그아웃 콜백을 해제해도 됨(이미 로그아웃 상태/또는 루트가 로그인)
        // 중복 라우팅(콜백 재호출) 방지 목적
        LoginManager.shared.onForceLogout = nil

        // 이미 로그인 화면이면 또 갈 필요 없음
        if isShowingLogin { return }
        isShowingLogin = true

        if window.windowScene == nil { window.windowScene = windowScene }

        let loginVC = LoginCompositionRoot.makeLoginViewController(
            authRepository: socialAuthRepository,
            onLoginSuccess: { [weak self] authenticatedUser in
                guard let self else { return }
                LoginManager.shared.setAuthenticatedUser(authenticatedUser)

                Task { [weak self] in
                    guard let self else { return }
                    await self.routeAfterAuthenticated()
                }
            }
        )

        let nav = UINavigationController(rootViewController: loginVC)
        nav.isNavigationBarHidden = true
        setRoot(nav, animated: true)
    }

    @MainActor
    private func showMainTab(initialTabIndex: Int? = nil) {
        // 메인 탭으로 들어가면 다시 콜백을 설치(강제 로그아웃 처리 활성화)
        isShowingLogin = false
        self.profileCoordinator = nil
        installForceLogoutHandler()

        // 메인 탭 수명 동안 LookbookContainer(공유 VM/캐시)를 유지
        let lbcontainer = ensureLookbookContainer()
        let chatContainer = ensureChatContainer()

        // 탭 조립은 MainTabCompositionRoot가 담당 (CustomTabBarVC는 룩북을 모름)
        let tab = MainTabCompositionRoot.makeMainTab(
            lookbookContainer: lbcontainer,
            chatContainer: chatContainer,
            currentUserProvider: currentUserProvider,
            myPageContainer: makeMyPageContainer()
        )
        self.mainTabController = tab

        setRoot(tab, animated: true)
        if let initialTabIndex {
            tab.selectTab(initialTabIndex)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.appSessionRuntime.startAuthenticatedSession(
                joinedRoomsStore: self.joinedRoomsStore,
                brandAdminSessionStore: self.brandAdminSessionStore
            )
            self.consumePendingNotificationRouteIfPossible()
        }
    }

    @MainActor
    private func showProfileFlow(userID: String) {
        print("[AppCoordinator] showProfileFlow")
        isShowingLogin = false
        installForceLogoutHandler()

        let nav = UINavigationController()
        nav.isNavigationBarHidden = true
        nav.view.backgroundColor = OutPickTheme.ColorToken.backgroundBase

        self.profileCoordinator = ProfileCoordinator(
            navigationController: nav,
            userID: userID,
            moodRepository: styleMoodRepository,
            checkNicknameAvailabilityUseCase: checkNicknameAvailabilityUseCase,
            completeOnboardingUseCase: completeOnboardingUseCase,
            onCompleted: { [weak self] outcome in
                guard let self else { return }
                Task { @MainActor in
                    self.currentUserSessionStore.replaceProfile(outcome.publicProfile)
                    _ = self.ensureChatContainer()
                }
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await LoginManager.shared.bootstrapAfterLogin(
                            joinedRoomsStore: self.joinedRoomsStore,
                            joinedRoomsRuntime: self.appSessionRuntime,
                            brandAdminSessionStore: self.brandAdminSessionStore
                        )
                    } catch {
                        print("bootstrapAfterLogin 실패(프로필 완료): \(error)")
                    }
                    await MainActor.run {
                        self.prewarmLookbookHome()
                        self.showMainTab()  // 완료 후 메인 탭으로
                        if outcome.avatarUploadFailed {
                            self.showAvatarUploadWarning()
                        }
                    }
                }
            }
        )
        self.profileCoordinator?.start()

        setRoot(nav, animated: true)
    }

    @MainActor
    private func showAuthenticatedBootstrapFailure() {
        let failure = AppBootstrapFailureViewController { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                await self?.routeAfterAuthenticated()
            }
        }
        setRoot(failure, animated: true)
    }

    @MainActor
    private func showDeletionPending() {
        let controller = AccountDeletionPendingViewController {
            LoginManager.shared.logout()
        }
        setRoot(controller, animated: true)
    }

    @MainActor
    private func showAvatarUploadWarning() {
        guard let presenter = mainTabController else { return }
        let alert = UIAlertController(
            title: "프로필 사진을 저장하지 못했어요",
            message: "계정과 관심 스타일은 저장됐어요. 프로필 사진은 나중에 다시 설정할 수 있어요",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        presenter.present(alert, animated: true)
    }

    @MainActor
    func setRoot(_ vc: UIViewController, animated: Bool) {
        if animated {
            UIView.transition(with: window, duration: 0.2, options: .transitionCrossDissolve) {
                self.window.rootViewController = vc
            }
        } else {
            self.window.rootViewController = vc
        }

        self.window.makeKeyAndVisible()
    }

    @MainActor
    private func prewarmLookbookHome() {
        ensureLookbookContainer().preloadLookbook()
    }

    @MainActor
    private func ensureLookbookContainer() -> LookbookContainer {
        if let lookbookContainer {
            return lookbookContainer
        }

        let created = LookbookContainer(
            provider: lookbookProvider,
            brandAdminSessionStore: brandAdminSessionStore,
            currentUserProvider: currentUserProvider,
            publicProfileRepository: publicProfileRepository,
            avatarImageManager: avatarImageManager
        )
        self.lookbookContainer = created
        return created
    }

    private func makeMyPageContainer() -> MyPageContainer {
        MyPageContainer(
            userID: currentUserProvider.canonicalUserID,
            accountRepository: accountRepository,
            publicProfileRepository: publicProfileRepository,
            moodRepository: styleMoodRepository,
            updatePublicProfileUseCase: updatePublicProfileUseCase,
            updateStylePreferencesUseCase: updateStylePreferencesUseCase,
            sessionStore: currentUserSessionStore,
            currentUserProvider: currentUserProvider,
            avatarImageManager: avatarImageManager
        )
    }

    @MainActor
    private func ensureChatContainer() -> ChatContainer {
        if let chatContainer {
            return chatContainer
        }

        let created = ChatContainer(
            persistence: chatPersistence,
            publicProfileRepository: publicProfileRepository,
            joinedRoomsStore: joinedRoomsStore,
            joinedRoomsRuntime: appSessionRuntime,
            currentUserProvider: currentUserProvider,
            realtimeSocketService: realtimeSocketService,
            avatarImageManager: avatarImageManager
        )
        self.chatContainer = created
        return created
    }

    @MainActor
    func consumePendingNotificationRouteIfPossible() {
        guard LoginManager.shared.hasAuthenticatedIdentity else { return }
        guard let route = NotificationRouter.shared.consumePendingRoute() else { return }
        guard let mainTabController else {
            NotificationRouter.shared.setPendingRoute(route)
            return
        }

        mainTabController.selectTab(1)

        guard let builder = mainTabController.tabBuilder as? DefaultMainTabBuilder,
              let presenter = mainTabController.activeContentViewController else {
            NotificationRouter.shared.setPendingRoute(route)
            return
        }

        Task { @MainActor in
            do {
                try await builder.openChatRoom(roomID: route.roomID, from: presenter)
            } catch {
                print("[AppCoordinator] failed to open push route room(\(route.roomID)): \(error)")
            }
        }
    }

    @MainActor
    func handleSceneDidBecomeActive() async {
        await appSessionRuntime.handleSceneDidBecomeActive()
        consumePendingNotificationRouteIfPossible()
    }

    @MainActor
    func handleSceneWillResignActive() async {
        await appSessionRuntime.handleSceneWillResignActive()
    }

    @MainActor
    func handleSceneDidEnterBackground() async {
        await appSessionRuntime.handleSceneDidEnterBackground()
    }

    #if DEBUG
    @MainActor
    private func routeForUITestAuthenticatedSessionIfNeeded(
        processInfo: ProcessInfo = .processInfo
    ) -> Bool {
        guard processInfo.environment["UITESTS"] == "1",
              processInfo.arguments.contains("--uitest-authenticated") else {
            return false
        }

        let shouldUseFixture = processInfo.arguments.contains("--uitest-lookbook-fixture")
        if processInfo.arguments.contains("--uitest-test-firebase") {
            Task { [weak self] in
                await self?.routeForTestFirebaseUITestSession(processInfo: processInfo)
            }
            return true
        }

        let authenticatedUser = AuthenticatedUser(
            identityKey: "uitest-user",
            provider: .google,
            providerUserID: "uitest-user",
            email: "uitest@outpick.local"
        )
        LoginManager.shared.setAuthenticatedUser(authenticatedUser)
        currentUserSessionStore.replaceProfile(
            UserPublicProfile(
                userID: authenticatedUser.identityKey,
                nickname: "UI 테스트",
                avatarThumbPath: nil,
                avatarOriginalPath: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        if shouldUseFixture {
            let fixtureProvider = LookbookUITestFixtureRepositoryProviderFactory.makeProvider()
            lookbookContainer = LookbookContainer(
                provider: fixtureProvider,
                brandAdminSessionStore: brandAdminSessionStore,
                currentUserProvider: currentUserProvider,
                avatarImageManager: avatarImageManager
            )
            brandAdminSessionStore.applyUITestWritableBrands([
                LookbookUITestFixtureRepositoryProviderFactory.brandID
            ])
        }

        prewarmLookbookHome()
        showMainTab(initialTabIndex: 2)
        return true
    }

    private func routeForTestFirebaseUITestSession(processInfo: ProcessInfo) async {
        let email = processInfo.environment["OUTPICK_TEST_FIREBASE_USER_EMAIL"] ?? "uitest@outpick.local"
        let password = processInfo.environment["OUTPICK_TEST_FIREBASE_USER_PASSWORD"] ?? "OutPickUITest-2026"

        do {
            let firebaseUser = try await signInTestFirebaseUser(email: email, password: password)
            let authenticatedUser = AuthenticatedUser(
                identityKey: firebaseUser.uid,
                provider: .google,
                providerUserID: firebaseUser.uid,
                email: firebaseUser.email ?? email
            )
            LoginManager.shared.setAuthenticatedUser(authenticatedUser)
            currentUserSessionStore.replaceProfile(
                UserPublicProfile(
                    userID: firebaseUser.uid,
                    nickname: firebaseUser.displayName ?? "UI 테스트",
                    avatarThumbPath: nil,
                    avatarOriginalPath: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            )
        } catch {
            print("[AppCoordinator] Test Firebase Auth sign-in failed: \(error)")
        }

        prewarmLookbookHome()
        showMainTab(initialTabIndex: 2)
    }

    private func signInTestFirebaseUser(email: String, password: String) async throws -> FirebaseAuth.User {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let user = result?.user else {
                    continuation.resume(throwing: TestFirebaseAuthError.missingUser)
                    return
                }

                continuation.resume(returning: user)
            }
        }
    }

    private enum TestFirebaseAuthError: Error {
        case missingUser
    }
    #endif
}
