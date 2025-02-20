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
              guard let email = result?.user.email else { return }
              
              LoginManager.shared.fetchUserProfile(email) { screen in
                  
                  self.view.window?.rootViewController = screen
                  self.view.window?.makeKeyAndVisible()
                  
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
                        LoginManager.shared.getKakaoEmail { email in }

                        LoginManager.shared.fetchUserProfile(LoginManager.shared.getUserEmail) { screen in
                                DispatchQueue.main.async {
                                    self.view.window?.rootViewController = screen
                                    self.view.window?.makeKeyAndVisible()
                                }
                            }
//                        }
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
                        LoginManager.shared.getKakaoEmail { email in }
                            
                            LoginManager.shared.fetchUserProfile(LoginManager.shared.getUserEmail) { screen in
                                DispatchQueue.main.async {
                                    self.view.window?.rootViewController = screen
                                    self.view.window?.makeKeyAndVisible()
                                }
                            }
//                        }
                    }
                }
            }
        }
    }
}
