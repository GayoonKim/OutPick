//
//  MyMenuViewController.swift
//  OutPick
//
//  Created by 김가윤 on 12/16/24.
//

import UIKit
import KakaoSDKUser
import FirebaseAuth

class MyMenuViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func logOutBtnTapped(_ sender: UIButton) {
        KeychainManager.shared.delete(service: "GayoonKim.OutPick", account: "UserProfile")
        
        LoginManager.shared.getKakaoEmail{ result in
            if result {
                UserApi.shared.logout {(error) in
                    if let error = error {
                        print(error)
                    }
                    else {
                        print("logout() success.")
                        let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
                        let loginViewController = mainStoryboard.instantiateViewController(withIdentifier: "LoginVC")
                        self.view.window?.rootViewController = loginViewController
                        self.view.window?.makeKeyAndVisible()
                    }
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
