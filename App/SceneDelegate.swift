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
import FirebaseAuth
import Combine

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// 앱 전역 RepositoryProvider (Firestore/Storage 등 의존성 묶음)
    private let repositoryProvider: RepositoryProvider = .shared

    /// 로그인 성공 후 룩북(브랜드/로고) 프리로드를 위한 앱 전역 컨테이너
    private var appContainer: AppContainer?


    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            if (AuthApi.isKakaoTalkLoginUrl(url)) {
                _ = AuthController.handleOpenUrl(url: url)
            }
        }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // window를 직접 생성/보관해야 시스템이 기본 storyboard root를 자동으로 띄우지 않음
        // (그렇지 않으면 CustomTabBarViewController가 SceneDelegate 주입 없이 먼저 로드되어 container nil 크래시 발생 가능)
        if self.window == nil {
            self.window = UIWindow(windowScene: windowScene)
        }

        // 초기 화면(로딩 화면)을 즉시 세팅 (window가 준비된 뒤에 root를 설정)
        self.window?.overrideUserInterfaceStyle = .light
        let storyboard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        let initialViewController = storyboard.instantiateViewController(withIdentifier: "LaunchScreen")
        self.window?.rootViewController = initialViewController
        self.window?.makeKeyAndVisible()

        print("2. DispatchQueue 시작 전")

        DispatchQueue.global(qos: .userInitiated).async {
            print("DispatchQueue 내부 시작")

            let group = DispatchGroup()
            var isLoggedIn = false

            // 구글 로그인 확인
            print("구글 로그인 체크 시작")
            group.enter()
            self.checkGoogleLogin { success in
                print("구글 로그인 체크 완료: \(success)")
                isLoggedIn = success
                group.leave()
            }

            // 카카오 로그인 확인
            print("카카오 로그인 체크 시작")
            group.enter()
            self.checkKakaoLogin { success in
                print("카카오 로그인 체크 완료: \(success)")
                if success {
                    isLoggedIn = true
                }
                group.leave()
            }

            print("notify 설정 전")
            group.notify(queue: .main) {
                print("notify 내부 실행")
                if isLoggedIn {
                    print("로그인 됨")
                    Task {
                        do {
                            // 1️⃣ 프로필 기반 초기 화면 결정
                            let screen = try await LoginManager.shared.makeInitialViewController()

                            // 로그인 성공 후 룩북 프리로드를 위해 AppContainer를 단일 인스턴스로 유지
                            let container: AppContainer = await MainActor.run {
                                if self.appContainer == nil {
                                    self.appContainer = AppContainer(provider: self.repositoryProvider)
                                }
                                return self.appContainer!
                            }

                            // ✅ CustomTabBarViewController로 이동하는 경우 동일 컨테이너를 주입(주입 후 view를 미리 로드)
                            await self.injectAppContainer(container, into: screen)

                            // ✅ 화면 전환
                            await MainActor.run {
                                self.window?.rootViewController = screen
                                self.window?.makeKeyAndVisible()
                            }

                            // ✅ 룩북: 브랜드 20개 + 첫 화면용 로고 N개(썸네일) 프리로드 시작
                            await MainActor.run {
                                container.preloadLookbook()
                            }

                            // ✅ 로그인 성공 후 프로필 리스너 시작
                            FirebaseManager.shared.listenToUserProfile(email: LoginManager.shared.getUserEmail)

                            // ✅ 참여 방 선 주입 (첫 진입 지연 없앰)
                            if let profile = LoginManager.shared.currentUserProfile {
                                await FirebaseManager.shared.joinedRoomStore.replace(with: profile.joinedRooms)
                            }

                            try await FirebaseManager.shared.fetchTopRoomsPage(limit: 30)

                            // 2️⃣ 소켓/핫룸은 항상 실행
                            async let _ = SocketIOManager.shared.establishConnection()

                            // 3️⃣ 참여중인 방은 프로필 있는 경우에만 등록
                            if screen is CustomTabBarViewController {
                                guard let profile = LoginManager.shared.currentUserProfile else { return }

                                let joinedRooms = profile.joinedRooms
                                BannerManager.shared.start(for: joinedRooms)

                                Task .detached { await FirebaseManager.shared.startListenRoomDocs(roomIDs: joinedRooms) }
                                for roomID in joinedRooms {
                                    SocketIOManager.shared.joinRoom(roomID)
                                }

                                print("📢 BannerManager: \(joinedRooms.count)개 방에 대해 리스닝 시작")
                            } else {
                                print("🆕 신규 유저: BannerManager 등록 스킵")
                            }

                        } catch {
                            print("❌ 초기화 실패:", error)
                        }
                    }
                } else {
                    print("로그인 안 됨")
                    self.showLoginViewController(windowScene: windowScene)
                }
            }
        }
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

        currentUser.getIDTokenForcingRefresh(true) { _, error in
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

    private func showLoginViewController(windowScene: UIWindowScene) {
        // window가 없을 수 있는 경로 대비
        if self.window == nil {
            self.window = UIWindow(windowScene: windowScene)
        }

        let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let loginViewController = mainStoryboard.instantiateViewController(withIdentifier: "LoginVC")

        self.window?.rootViewController = loginViewController
        self.window?.makeKeyAndVisible()
    }

    /// CustomTabBarViewController(또는 이를 root로 가진 NavigationController)에 AppContainer를 주입하고,
    /// 주입 후에는 view를 미리 로드해 container nil 타이밍 이슈를 방지합니다.
    @MainActor
    private func injectAppContainer(_ container: AppContainer, into screen: UIViewController) {
        
        if let tab = screen as? CustomTabBarViewController {
            print("Injecting into:", ObjectIdentifier(tab))
            tab.container = container
            // 주입 후 view를 미리 로드하여 viewDidLoad 시점에 container가 nil이 되지 않도록 보장
            tab.loadViewIfNeeded()
            // (선택) Lookbook 탭 캐시를 확실히 초기화
            tab.invalidateLookbookTabCache(reloadIfVisible: false)
            return
        }

        if let nav = screen as? UINavigationController,
           let tab = nav.viewControllers.first as? CustomTabBarViewController {
            tab.container = container
            tab.loadViewIfNeeded()
            tab.invalidateLookbookTabCache(reloadIfVisible: false)
        }
    }
}
