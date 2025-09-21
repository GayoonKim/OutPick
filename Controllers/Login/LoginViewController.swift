//
//  LoginViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/1/24.
//

import UIKit
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser
import FirebaseFirestore
import GoogleSignIn
import FirebaseCore
import FirebaseAuth

class LoginViewController: UIViewController {
    
    @IBOutlet weak var googleSignInBtn: GIDSignInButton!
    @IBOutlet weak var kakaoSignInBtn: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func googleSignInBtnPressed(_ sender: GIDSignInButton) {
        self.loginWithGoogle()
    }
    
    @MainActor
    private func loginWithGoogle() {
        // Firebase client ID 불러오기.
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        
        // Google Sign In configuration object 생성.
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // 로그인 요청
        GIDSignIn.sharedInstance.signIn(withPresenting: self) { [unowned self] result, error in
            guard error == nil else {
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString
            else {
                return
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
            
            Auth.auth().signIn(with: credential) { result, error in
                LoginManager.shared.getGoogleEmail { success in
                    self.commonLogingProcess()
                }
            }
        }
    }

    @IBAction func kakaoLoginBtnPressed(_ sender: UIButton) {
        self.loginWithKakao()
    }
    
    private func loginWithKakao() {
        if (UserApi.isKakaoTalkLoginAvailable()) {
            UserApi.shared.loginWithKakaoTalk {(oauthToken, error) in
                if let error = error {
                    print(error)
                }
                else {
                    print("loginWithKakaoTalk() success.")
                    
                    self.dismiss(animated: true) {
                        //do something
                        LoginManager.shared.getKakaoEmail { success in
                            if success {
                                self.commonLogingProcess()
                            }
                        }
                    }

                }
            }
        } else {
            UserApi.shared.loginWithKakaoAccount {(oauthToken, error) in
                if let error = error {
                    print(error)
                } else {
                    print("loginWithKakaoAccount() success.")
                    
                    self.dismiss(animated: true) {
                        //                        do something
                        LoginManager.shared.getKakaoEmail { success in
                            if success {
                                self.commonLogingProcess()
                            }
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    private func commonLogingProcess() {
        Task {
            do {
                try await LoginManager.shared.updateLogDevID()
                try await LoginManager.shared.setupDevIDListener()
                try await FirebaseManager.shared.listenToHotRooms()
                SocketIOManager.shared.establishConnection {
                    SocketIOManager.shared.listenToChatMessage()
                }
                
                let screen = try await LoginManager.shared.fetchProfileFromFirebase(LoginManager.shared.getUserEmail)
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let window = scene.windows.first else { return }

                UIView.transition(with: window,
                                  duration: 0.3,
                                  options: .transitionCrossDissolve,
                                  animations: {
                                      window.rootViewController = screen
                                  },
                                  completion: nil)

                window.makeKeyAndVisible()
    
            } catch {
                print("로그인 후처리 실패: \(error)")
                AlertManager.showAlertNoHandler(title: "로그인 실패", message: "로그인에 실패했습니다. 다시 시도해주세요.", viewController: self)
            }
        }
    }
    
//    private func showLoginViewController() {
//        let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
//        let loginViewController = mainStoryboard.instantiateViewController(withIdentifier: "LoginVC")
//        
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
//               let window = scene.windows.first {
//                UIView.transition(
//                    with: window,
//                    duration: 0.3,
//                    options: .transitionCrossDissolve,
//                    animations: {
//                        window.rootViewController = loginViewController
//                    },
//                    completion: nil
//                )
//                window.makeKeyAndVisible()
//            }
//            
//        }
//    }
}
