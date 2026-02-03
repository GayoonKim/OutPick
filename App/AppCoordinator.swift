//
//  AppCoordinator.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

final class AppCoordinator {

    private let window: UIWindow
    private weak var currentWindowScene: UIWindowScene?

    private let provider: LookbookRepositoryProvider = .shared
    private var lookbookContainer: LookbookContainer?

    init(window: UIWindow) {
        self.window = window

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForceLogout),
            name: LoginManager.forceLogoutNotification,
            object: nil
        )
    }

    func start(windowScene: UIWindowScene) {
        self.currentWindowScene = windowScene

        // 필요하면 Launch 표시
        // showLaunchScreen()

        Task { [weak self] in
            guard let self else { return }

            let ok = await LoginManager.shared.checkExistingLogin()
            if ok {
                await self.routeAfterAuthenticated(windowScene: windowScene)
            } else {
                await MainActor.run { self.showLogin(windowScene: windowScene) }
            }
        }
    }

    private func routeAfterAuthenticated(windowScene: UIWindowScene) async {
        let profileResult = await LoginManager.shared.loadUserProfile()

        switch profileResult {
        case .success:
            // 새 기기 로그인 = 기존 기기 로그아웃 정책 시작점
            do {
                try await LoginManager.shared.updateLogDevID()
            }
            catch {
                print("updateLogDevID 실패: \(error)")
            }

            await MainActor.run { self.showMainTab() }

        case .failure:
            await MainActor.run { self.showProfileFlow() }
        }
    }

    @objc private func handleForceLogout() {
        guard let scene = currentWindowScene else { return }
        Task { @MainActor in
            self.showLogin(windowScene: scene)
        }
    }

    // MARK: - Screens

    @MainActor
    private func showLogin(windowScene: UIWindowScene) {
        if window.windowScene == nil { window.windowScene = windowScene }

        let loginVC = LoginCompositionRoot.makeLoginViewController(
            onLoginSuccess: { [weak self] email in
                guard let self else { return }
                LoginManager.shared.setUserEmail(email)
                Task { await self.routeAfterAuthenticated(windowScene: windowScene) }
            }
        )

        let nav = UINavigationController(rootViewController: loginVC)
        nav.isNavigationBarHidden = true
        setRoot(nav)
    }

    @MainActor
    private func showMainTab() {
        if lookbookContainer == nil {
            lookbookContainer = LookbookContainer(provider: provider)
        }
        guard let container = lookbookContainer else { return }

        let tab = CustomTabBarViewController()
        tab.container = container
        tab.loadViewIfNeeded()

        setRoot(tab)
    }

    @MainActor
    private func showProfileFlow() {
        // 아직 Profile이 storyboard 기반이면 임시 유지
        let sb = UIStoryboard(name: "Main", bundle: nil)
        let profileNav = sb.instantiateViewController(withIdentifier: "ProfileNav")
        setRoot(profileNav)
    }

    @MainActor
    private func setRoot(_ root: UIViewController) {
        UIView.transition(
            with: window,
            duration: 0.25,
            options: .transitionCrossDissolve,
            animations: { self.window.rootViewController = root },
            completion: nil
        )
        window.makeKeyAndVisible()
    }
}
