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
import CoreLocation
import FirebaseAuth

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    
    private let locationManager = CLLocationManager()

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            if (AuthApi.isKakaoTalkLoginUrl(url)) {
                _ = AuthController.handleOpenUrl(url: url)
            }
        }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let _ = (scene as? UIWindowScene) else { return }
        window?.overrideUserInterfaceStyle = .light
        
        // 초기 화면을 로딩 화면으로 설정
        let storyboard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        let initialViewController = storyboard.instantiateViewController(withIdentifier: "LaunchScreen")
        window?.rootViewController = initialViewController
        window?.makeKeyAndVisible()
        
        WeatherAPIManager.shared.startLocationUpdates()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            var isLoggedIn = false
            
            // 구글 로그인 확인
            group.enter()
            self.checkGoogleLogin { success in
                if success {
                    isLoggedIn = true
                    
                    // 채팅방 목록 감지 시작
                    FirestoreManager.shared.listenForChatRooms { rooms in
                        print("채팅방 목록 수: \(rooms.count)")
                    }
                }
                group.leave()
            }
            
            // 카카오 로그인 확인
            group.enter()
            self.checkKakaoLogin { success in
                if success {
                    isLoggedIn = true
                    
                    // 채팅방 목록 감지 시작
                    FirestoreManager.shared.listenForChatRooms { rooms in
                        print("채팅방 목록 수: \(rooms.count)")
                    }
                }
                group.leave()
            }
            
            group.notify(queue: .main) {
                if !isLoggedIn {
                    self.showLoginViewController()
                }
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
        
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.

    }
    
    // 카카오 로그인 여부 확인
    private func checkKakaoLogin(completion: @escaping (Bool) -> Void) {
        if AuthApi.hasToken() {
            UserApi.shared.accessTokenInfo { (_, error) in
                if let error = error {
                    if let sdkError = error as? SdkError, sdkError.isInvalidTokenError() == true {
                        // 토큰이 유효하지 않기 때문에 재로그인 필요
                        print("재로그인 필요.")
//                        self.showLoginViewController()
                        completion(false)
                    } else {
                        print("토큰 확인 오류: \(error)")
//                        self.showLoginViewController()
                        completion(false)
                    }
                } else {
                    // 유효한 토큰, 자동 로그인 상태 유지
                    print("이미 로그인 상태.")
//                    
//                    // 실시간으로 채팅방 목록 감지
//                    FirestoreManager.shared.listenForChatRooms { rooms in
//                        print("채팅방 목록 수: \(rooms.count)")
//                    }
                    
                    // 사용자 이메일 불러오기
                    LoginManager.shared.getKakaoEmail { email in
                        guard let email = email else {
//                            self.showLoginViewController()
                            completion(false)
                            return
                        }
                        
                        // 이메일을 통해 프로필 불러오기
                        LoginManager.shared.fetchUserProfile(email) { screen in
                            DispatchQueue.main.async {
                                self.window?.rootViewController = screen
                                self.window?.makeKeyAndVisible()
                            }
                            completion(true)
                        }
                    }
                }
            }
        } else {
            // 토큰이 없어 로그인 필요
            print("재로그인 필요.")
//            self.showLoginViewController()
            completion(false)
        }
    }
    
    // 구글 로그인 여부 확인
    private func checkGoogleLogin(completion: @escaping (Bool) -> Void) {
        let currentUser = Auth.auth().currentUser
        currentUser?.getIDTokenForcingRefresh(true) { idToken, error in
            if let error = error {
                print("토큰 불러오기 오류: \(error)")
                completion(false)
                return
            }
            
            guard let userEmail = currentUser?.email else {
                completion(false)
                return
            }
            LoginManager.shared.fetchUserProfile(userEmail) { screen in
                DispatchQueue.main.async {
                    self.window?.rootViewController = screen
                    self.window?.makeKeyAndVisible()
                }
                completion(true)
            }
        }
    }
    
    private func showLoginViewController() {
        let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let loginViewController = mainStoryboard.instantiateViewController(withIdentifier: "LoginVC")
        window?.rootViewController = loginViewController
        window?.makeKeyAndVisible()
    }
    
}
