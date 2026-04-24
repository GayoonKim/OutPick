//
//  AppCoordinator.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

@MainActor
final class AppCoordinator {
    static weak var activeCoordinator: AppCoordinator?

    private let window: UIWindow
    private weak var currentWindowScene: UIWindowScene?
    private weak var mainTabController: CustomTabBarViewController?

    private let lookbookProvider: LookbookRepositoryProvider
    private var lookbookContainer: LookbookContainer?
    private var chatContainer: ChatContainer?
    private let joinedRoomsStore = JoinedRoomsStore()
    private let brandAdminSessionStore = BrandAdminSessionStore()
    
    private var profileCoordinator: ProfileCoordinator?

    // Profile flow DI
    private let userProfileRepository: UserProfileRepositoryProtocol

    // 로그인 화면이 이미 떠있는데 또 showLogin()을 타는 걸 막기 위한 플래그
    private var isShowingLogin: Bool = false

    init(
        window: UIWindow,
        lookbookProvider: LookbookRepositoryProvider = .shared,
        userProfileRepository: UserProfileRepositoryProtocol
    ) {
        self.window = window
        self.lookbookProvider = lookbookProvider
        self.userProfileRepository = userProfileRepository
        self.window.backgroundColor = .systemBackground
        Self.activeCoordinator = self
    }

    @MainActor
    func start(windowScene: UIWindowScene) {
        self.currentWindowScene = windowScene

        // 앱 시작 시 강제 로그아웃 콜백 설치(메인 탭/프로필 플로우에서 사용)
        installForceLogoutHandler()

        setRoot(BootLoadingViewController(), animated: true)

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
        print("[AppCoordinator] routeAfterAuthenticated identity=\(LoginManager.shared.getAuthIdentityKey)")
        await MainActor.run { self.setRoot(BootLoadingViewController(), animated: false) }
        
        let profileResult = await LoginManager.shared.loadUserProfile()
        
        switch profileResult {
        case .success:
            print("[AppCoordinator] complete profile found. Showing main tab.")
            await MainActor.run {
                let chatContainer = self.ensureChatContainer()
                chatContainer.bindJoinedRoomsRuntimeIfNeeded()
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
                    brandAdminSessionStore: brandAdminSessionStore
                )
            } catch {
                print("bootstrapAfterLogin 실패: \(error)")
            }

            await MainActor.run { self.showMainTab() }

        case .failure(let error):
            print("[AppCoordinator] profile is missing/incomplete. Showing profile flow. error=\(error)")
            await MainActor.run { self.showProfileFlow() }
        }
    }

    // MARK: - 화면 전환

    @MainActor
    private func showLogin(windowScene: UIWindowScene) {
        self.joinedRoomsStore.clear()
        Task { @MainActor in
            await PresenceManager.shared.handleLogout()
        }
        SocketIOManager.shared.closeConnection()
        SocketIOManager.shared.resetRoomMembership()

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
    private func showMainTab() {
        // 메인 탭으로 들어가면 다시 콜백을 설치(강제 로그아웃 처리 활성화)
        isShowingLogin = false
        self.profileCoordinator = nil
        installForceLogoutHandler()

        // 메인 탭 수명 동안 LookbookContainer(공유 VM/캐시)를 유지
        let lbcontainer = ensureLookbookContainer()
        let chatContainer = ensureChatContainer()
        chatContainer.bindJoinedRoomsRuntimeIfNeeded()

        // 탭 조립은 MainTabCompositionRoot가 담당 (CustomTabBarVC는 룩북을 모름)
        let tab = MainTabCompositionRoot.makeMainTab(lookbookContainer: lbcontainer, chatContainer: chatContainer)
        self.mainTabController = tab

        setRoot(tab, animated: true)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await PresenceManager.shared.startAuthenticatedSession()
            self.consumePendingNotificationRouteIfPossible()
        }
    }

    @MainActor
    private func showProfileFlow() {
        print("[AppCoordinator] showProfileFlow")
        isShowingLogin = false
        installForceLogoutHandler()

        let nav = UINavigationController()
        nav.isNavigationBarHidden = true
        nav.view.backgroundColor = .systemBackground

        self.profileCoordinator = ProfileCoordinator(
            navigationController: nav,
            repository: userProfileRepository,
            onCompleted: { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    let chatContainer = self.ensureChatContainer()
                    chatContainer.bindJoinedRoomsRuntimeIfNeeded()
                }
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await LoginManager.shared.bootstrapAfterLogin(
                            joinedRoomsStore: self.joinedRoomsStore,
                            brandAdminSessionStore: self.brandAdminSessionStore
                        )
                    } catch {
                        print("bootstrapAfterLogin 실패(프로필 완료): \(error)")
                    }
                    await MainActor.run {
                        self.prewarmLookbookHome()
                        self.showMainTab()  // 완료 후 메인 탭으로
                    }
                }
            }
        )
        self.profileCoordinator?.start()

        setRoot(nav, animated: true)
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
            brandAdminSessionStore: brandAdminSessionStore
        )
        self.lookbookContainer = created
        return created
    }

    @MainActor
    private func ensureChatContainer() -> ChatContainer {
        if let chatContainer {
            return chatContainer
        }

        let created = ChatContainer(joinedRoomsStore: joinedRoomsStore)
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

        mainTabController.switchScreen(1)

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
}
