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

class LoginViewController: UIViewController {
    
    let kakaoLoginManager = KakaoLoginManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
//    private func checkKakaoLogin() {
//        if AuthApi.hasToken() {
//            UserApi.shared.accessTokenInfo { (_, error) in
//                if let error = error {
//                    if let sdkError = error as? SdkError, sdkError.isInvalidTokenError() == true {
//                        // 토큰이 유효하지 않기 때문에 재로그인 필요
//                        print("재로그인 필요.")
//                    } else {
//                        print("토큰 확인 오류: \(error)")
//                    }
//                } else {
//                    // 유효한 토큰, 자동 로그인 상태 유지
//                    print("이미 로그인 상태.")
//                    
//                    UserApi.shared.me() {(user, error) in
//                        if let error = error {
//                            print(error)
//                        } else {
//                            print("me() 성공")
//                            
//                            // 사용자 이메일로 프로필 설정 여부 확인
//                            guard let userEmail = user?.kakaoAccount?.email else { return }
//                            self.fetchUserProfile(userEmail)
//                        }
//                    }
//                    
//                    
//                }
//            }
//        } else {
//            // 토큰이 없어 로그인 필요
//            print("재로그인 필요.")
//        }
//    }
    
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
                        self.kakaoLoginManager.getEmail { email in
                            guard let email = email else {
                                return
                            }
                            
                            self.kakaoLoginManager.fetchUserProfile(email) { screen in
                                DispatchQueue.main.async {
                                    self.view.window?.rootViewController = screen
                                    self.view.window?.makeKeyAndVisible()
                                }
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
                        //do something
                        self.kakaoLoginManager.getEmail { email in
                            guard let email = email else {
                                return
                            }
                            
                            self.kakaoLoginManager.fetchUserProfile(email) { screen in
                                DispatchQueue.main.async {
                                    self.view.window?.rootViewController = screen
                                    self.view.window?.makeKeyAndVisible()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Firestore에서 사용자 이메일로 만들어진 프로필 문서 쿼리
    private func fetchUserProfile(_ email: String) {
        FirestoreManager.shared.fetchUserProfileFromFirestore(email: email) { result in
            switch result {
            case .success(let userProfile):
                print("User Profile: \(userProfile)")
                UserProfile.sharedUserProfile = userProfile
                let homeVC = self.storyboard?.instantiateViewController(identifier: "HomeTBC") as? UITabBarController
                self.view.window?.rootViewController = homeVC
                self.view.window?.makeKeyAndVisible()
                
            case .failure(let error):
                print("Failed to fetch user profile: \(error.localizedDescription)")
                let firstProfileVC = self.storyboard?.instantiateViewController(identifier: "FirstProfileVC") as? UIViewController
                self.view.window?.rootViewController = firstProfileVC
                self.view.window?.makeKeyAndVisible()
            }
        }
    }
}
