//
//  SceneDelegate.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import UIKit
import OSLog
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser
import GoogleSignIn

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static let bootstrapLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OutPick",
        category: "AppBootstrap"
    )

    var window: UIWindow?
    private var coordinator: AppCoordinator?
    private let bootstrapFailureInjector = AppBootstrapFailureInjector()
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        
        // Kakao login callback
        if AuthApi.isKakaoTalkLoginUrl(url) {
            _ = AuthController.handleOpenUrl(url: url)
            return
        }
        
        // GoogleSignIn callback
        _ = GIDSignIn.sharedInstance.handle(url)
    }
    
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        
        guard let windowScene = scene as? UIWindowScene else { return }
        
        if window == nil {
            window = UIWindow(windowScene: windowScene)
        }
        guard let window else { return }

        if let notificationResponse = connectionOptions.notificationResponse {
            NotificationRouter.shared.storePendingRoute(from: notificationResponse.notification.request.content.userInfo)
        }

        startApplication(window: window, windowScene: windowScene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Task { @MainActor in
            guard let coordinator else { return }
            await coordinator.handleSceneDidBecomeActive()
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Task { @MainActor in
            await coordinator?.handleSceneWillResignActive()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Task { @MainActor in
            await coordinator?.handleSceneDidEnterBackground()
        }
    }

    private func startApplication(window: UIWindow, windowScene: UIWindowScene) {
        if let coordinator {
            coordinator.start(windowScene: windowScene)
            return
        }

        do {
            let coordinator = try AppCompositionRoot.makeCoordinator(
                window: window,
                makeDatabase: makeDatabase
            )
            self.coordinator = coordinator
            coordinator.start(windowScene: windowScene)
        } catch {
            self.coordinator = nil
            Self.bootstrapLogger.error("앱 bootstrap에 실패했습니다: \(String(describing: error), privacy: .private)")
            showBootstrapFailure(window: window, windowScene: windowScene)
        }
    }

    private func makeDatabase() throws -> AppDatabase {
        try bootstrapFailureInjector.throwIfNeeded()
        return try AppDatabase.live()
    }

    private func showBootstrapFailure(window: UIWindow, windowScene: UIWindowScene) {
        let failureViewController = AppBootstrapFailureViewController { [weak self, weak window, weak windowScene] in
            guard let self, let window, let windowScene else { return }
            self.startApplication(window: window, windowScene: windowScene)
        }
        window.rootViewController = failureViewController
        window.makeKeyAndVisible()
    }
}
