//
//  MyMenuViewController.swift
//  OutPick
//
//  Created by 김가윤 on 12/16/24.
//

import UIKit
import KakaoSDKUser
import KakaoSDKCommon
import FirebaseAuth
import GoogleSignIn

class MyMenuViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func goToLoginScreen() {
        let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let loginViewController = mainStoryboard.instantiateViewController(withIdentifier: "LoginVC")
        self.view.window?.rootViewController = loginViewController
        self.view.window?.makeKeyAndVisible()
    }
    
    @IBAction func logOutBtnTapped(_ sender: UIButton) {
        KeychainManager.shared.delete(service: "GayoonKim.OutPick", account: "UserProfile")
        
        LoginManager.shared.getGoogleEmail { result in
            if result {
                do {
                    try Auth.auth().signOut()
                    GIDSignIn.sharedInstance.signOut()
                    self.goToLoginScreen()
                } catch {
                    print("Sign out error: \(error)")
                    self.goToLoginScreen()
                }
            }
        }
        
        LoginManager.shared.getKakaoEmail { result in
            if result {
                if UserApi.isKakaoTalkLoginAvailable() {
                    UserApi.shared.logout { error in
                        if let error = error {
                            if let sdkError = error as? SdkError,
                               case .ClientFailed(let reason, _) = sdkError,
                               case .TokenNotFound = reason {
                                print("이미 로그아웃 상태 (토큰 없음), 무시")
                            }
                        }
                    }
                }
                
                self.goToLoginScreen()
            }
        }
    }
}
