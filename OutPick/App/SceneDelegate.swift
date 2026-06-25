//
//  SceneDelegate.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import UIKit
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser
import GoogleSignIn

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    private var coordinator: AppCoordinator?
    
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

        if coordinator == nil {
            coordinator = AppCompositionRoot.makeCoordinator(window: window)
        }
        guard let coordinator else { return }

        if let notificationResponse = connectionOptions.notificationResponse {
            NotificationRouter.shared.storePendingRoute(from: notificationResponse.notification.request.content.userInfo)
        }
        
        coordinator.start(windowScene: windowScene)
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
}
