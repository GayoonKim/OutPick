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
        
        LoginManager.shared.getKakaoEmail { result in
            if result {
                if UserApi.isKakaoTalkLoginAvailable() {
                    UserApi.shared.logout { error in
                        if let error = error {
                            if let sdkError = error as? SdkError,
                               case .ClientFailed(let reason, _) = sdkError,
                               case .TokenNotFound = reason {
                                print("이미 로그아웃 상태 (토큰 없음), 무시")
                            } else {
                                print("Kakao logout error: \(error)")
                            }
                            // regardless of error, proceed to login screen
                            self.goToLoginScreen()
                        } else {
                            print("logout() success.")
                            self.goToLoginScreen()
                        }
                    }
                } else {
                    print("카카오톡 로그인이 아니었음 → 그냥 로그인 화면으로 이동")
                    self.goToLoginScreen()
                }
            } else {
                let firebaseAuth = Auth.auth()
                do {
                  try firebaseAuth.signOut()
                  let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
                  let loginViewController = mainStoryboard.instantiateViewController(withIdentifier: "LoginVC")
                  self.view.window?.rootViewController = loginViewController
                  self.view.window?.makeKeyAndVisible()
                } catch let signOutError as NSError {
                  print("Error signing out: %@", signOutError)
                }
            }
        }
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
