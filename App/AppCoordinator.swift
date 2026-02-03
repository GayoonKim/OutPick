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

    private let provider: LookbookRepositoryProvider
    private var lookbookContainer: LookbookContainer?

    // 로그인 화면이 이미 떠있는데 또 showLogin()을 타는 걸 막기 위한 플래그
    private var isShowingLogin: Bool = false

    init(window: UIWindow, provider: LookbookRepositoryProvider = .shared) {
        self.window = window
        self.provider = provider
    }

    @MainActor
    func start(windowScene: UIWindowScene) {
        self.currentWindowScene = windowScene

        // 한국어 주석: 앱 시작 시 강제 로그아웃 콜백 설치(메인 탭/프로필 플로우에서 사용)
        installForceLogoutHandler()

        setRoot(BootLoadingViewController(), animated: true)

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

    private func installForceLogoutHandler() {
        // 강제 로그아웃 이벤트는 콜백으로 수신해 루트 라우팅을 변경
        LoginManager.shared.onForceLogout = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                // 이미 로그인 화면이면 중복 라우팅 방지
                if self.isShowingLogin { return }

                // 메인 탭 상태 정리(선택)
                self.lookbookContainer = nil

                guard let scene = self.window.windowScene ?? self.currentWindowScene else { return }
                self.showLogin(windowScene: scene)
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

    // MARK: - 화면 전환

    @MainActor
    private func showLogin(windowScene: UIWindowScene) {
        // 로그인 화면으로 들어갈 땐 강제로그아웃 콜백을 해제해도 됨(이미 로그아웃 상태/또는 루트가 로그인)
        // 중복 라우팅(콜백 재호출) 방지 목적
        LoginManager.shared.onForceLogout = nil

        // 이미 로그인 화면이면 또 갈 필요 없음
        if isShowingLogin { return }
        isShowingLogin = true

        if window.windowScene == nil { window.windowScene = windowScene }

        let loginVC = LoginCompositionRoot.makeLoginViewController(
            onLoginSuccess: { [weak self] email in
                guard let self else { return }
                LoginManager.shared.setUserEmail(email)

                Task { [weak self] in
                    guard let self else { return }
                    await self.routeAfterAuthenticated(windowScene: windowScene)
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
        installForceLogoutHandler()

        // 메인 탭 수명 동안 LookbookContainer(공유 VM/캐시)를 유지
        if lookbookContainer == nil {
            lookbookContainer = LookbookContainer(provider: provider)
        }
        guard let lbcontainer = lookbookContainer else { return }

        // 탭 조립은 MainTabCompositionRoot가 담당 (CustomTabBarVC는 룩북을 모름)
        let tab = MainTabCompositionRoot.makeMainTab(lookbookContainer: lbcontainer)

        setRoot(tab, animated: true)
    }

    @MainActor
    private func showProfileFlow() {
        // 프로필 플로우도 인증 이후 상태이므로 강제 로그아웃 콜백은 활성화 유지
        isShowingLogin = false
        installForceLogoutHandler()

        // 아직 Profile이 storyboard 기반이면 임시 유지
        let sb = UIStoryboard(name: "Main", bundle: nil)
        let profileNav = sb.instantiateViewController(withIdentifier: "ProfileNav")
        setRoot(profileNav, animated: true)
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
}
