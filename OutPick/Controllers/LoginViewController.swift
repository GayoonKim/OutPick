//
//  LoginViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/1/24.
//

import UIKit
import KakaoSDKAuth
import KakaoSDKUser
import FirebaseFirestore

class LoginViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func kakaoLoginBtnPressed(_ sender: UIButton) {
        if (UserApi.isKakaoTalkLoginAvailable()) {
            UserApi.shared.loginWithKakaoTalk {(oauthToken, error) in
                if let error = error {
                    print(error)
                }
                else {
                    print("loginWithKakaoTalk() success.")

                    self.dismiss(animated: true) {
                        //do something
                        UserApi.shared.me() {(user, error) in
                            if let error = error {
                                print(error)
                            } else {
                                print("me() 성공")
                                
                                // 사용자 이메일로 프로필 설정 여부 확인
                                guard let userEmail = user?.kakaoAccount?.email else { return }
                                self.fetchUserProfile(userEmail)
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
                        
                        // 프로필 설정 여부 확인을 위한 이메일 불러오기
                        UserApi.shared.me() {(user, error) in
                            if let error = error {
                                print(error)
                            } else {
                                print("me() 성공")
                                
                                // 사용자 이메일로 프로필 설정 여부 확인
                                guard let userEmail = user?.kakaoAccount?.email else { return }
                                self.fetchUserProfile(userEmail)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Firestore에서 사용자 이메일로 만들어진 프로필 문서 쿼리
    private func fetchUserProfile(_ email: String) {
        fetchUserProfileFromFirestore(email: email) { result in
            switch result {
            case .success(let userProfile):
                print("User Profile: \(userProfile)")
                UserProfile.sharedUserProfile = userProfile
                let homeVC = self.storyboard?.instantiateViewController(identifier: "HomeVCTabBar") as? UITabBarController
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
