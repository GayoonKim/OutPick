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
import Combine

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    private var appCoordinator: AppCoordinator?
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            if (AuthApi.isKakaoTalkLoginUrl(url)) {
                _ = AuthController.handleOpenUrl(url: url)
            }
        }
    }
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        print("1. scene 메서드 시작")
    
        guard let _ = (scene as? UIWindowScene) else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.overrideUserInterfaceStyle = .light
            
            // 초기 화면을 로딩 화면으로 설정
            let storyboard = UIStoryboard(name: "LaunchScreen", bundle: nil)
            let initialViewController = storyboard.instantiateViewController(withIdentifier: "LaunchScreen")
            self.window?.rootViewController = initialViewController
            self.window?.makeKeyAndVisible()

            // AppCoordinator 초기화
            self.appCoordinator = AppCoordinator(window: self.window)
            self.appCoordinator?.start()
            
            // Banner 탭 시 해당 채팅방으로 이동
            BannerManager.shared.bannerTapped
                .sink { [weak self] roomID in
                    guard let self = self else { return }
                    
                    Task { @MainActor in
                        do {
                            // 우선 로컬(DB)에서 조회
                            var room = try GRDBManager.shared.fetchRoomInfo(roomID: roomID)
                            
                            // 만약 최신 데이터가 필요하면 서버에서도 업데이트
                            let serverRoom = try await FirebaseManager.shared.fetchRoomInfoWithID(roomID: roomID)
                            room = serverRoom
                            
                            guard let room = room else { return }
                            
                            // Coordinator를 통해 이동
                            self.appCoordinator?.showChatRoom(room: room, isRoomSaving: false)
                        } catch {
                            print("❌ room 정보를 불러오지 못했습니다:", error)
                        }
                    }
                }
                .store(in: &cancellables)
        }
        
        // 날씨 업데이트 시작
        WeatherAPIManager.shared.startLocationUpdates()
        print("1. WeatherAPIManager 시작")
        
        print("2. DispatchQueue 시작 전")
        
        DispatchQueue.global(qos: .userInitiated).async {
            print("3. DispatchQueue 내부 시작")
            
            let group = DispatchGroup()
            var isLoggedIn = false
            
            // 구글 로그인 확인
            print("4. 구글 로그인 체크 시작")
            group.enter()
            self.checkGoogleLogin { success in
                print("5. 구글 로그인 체크 완료: \(success)")
                isLoggedIn = success
                group.leave()
            }
            
            // 카카오 로그인 확인
            print("6. 카카오 로그인 체크 시작")
            group.enter()
            self.checkKakaoLogin { success in
                print("7. 카카오 로그인 체크 완료: \(success)")
                if success {
                    isLoggedIn = true
                }
                group.leave()
            }
            
            print("8. notify 설정 전")
            group.notify(queue: .main) {
                print("9. notify 내부 실행")
                if isLoggedIn {
                    print("10. 로그인 됨")
                        Task.detached {
                            try await FirebaseManager.shared.listenToHotRooms()
                            SocketIOManager.shared.establishConnection {
//                                SocketIOManager.shared.bindAllListenersIfNeeded()
                            }
                        }
                        
                        Task { @MainActor in
                            LoginManager.shared.fetchUserProfileFromKeychain { screen in
                                self.window?.rootViewController = screen
                                self.window?.makeKeyAndVisible()
                            }
                        }
                } else {
                    print("11. 로그인 안 됨")
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
                        print("재로그인 필요.")
                        completion(false)
                    } else {
                        print("토큰 확인 오류: \(error)")
                        completion(false)
                    }
                    return
                }
                
                print("이미 로그인 상태.")
                
                LoginManager.shared.getKakaoEmail { result in
                    completion(result)
                }
            }
        } else {
            print("재로그인 필요.")
            completion(false)
        }
    }

    // 구글 로그인 여부 확인
    private func checkGoogleLogin(completion: @escaping (Bool) -> Void) {
        
        guard let currentUser = Auth.auth().currentUser else {
            print("로그인 기록 없음")
            completion(false)
            return
        }
        
        currentUser.getIDTokenForcingRefresh(true) { idToken, error in
            if let error = error {
                print("토큰 불러오기 오류: \(error)")
                completion(false)
                return
            }
            
            LoginManager.shared.getGoogleEmail { result in
                completion(result)
            }
        }
    }
    
//    @MainActor
    private func showLoginViewController() {
        let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let loginViewController = mainStoryboard.instantiateViewController(withIdentifier: "LoginVC")
        
        self.window?.rootViewController = loginViewController
        self.window?.makeKeyAndVisible()
        
    }
}
