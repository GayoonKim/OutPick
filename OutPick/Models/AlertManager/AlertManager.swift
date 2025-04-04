//
//  AlertManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import UIKit
import FirebaseAuth
import KakaoSDKUser
import KakaoSDKAuth

class AlertManager {
    
    static let shared = AlertManager()
    
    @MainActor
    static func showAlertNoHandler(title: String, message: String, viewController: UIViewController) {
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default, handler: nil))
        viewController.present(alert, animated: true, completion: nil)
        
    }
    
    static func showDuplicateLoginAlert() {
        
        DispatchQueue.main.async {
            
            let alert = UIAlertController(title: "중복 로그인", message: "다른 기기에서 로그인이 감지되어 로그아웃 처리됩니다.", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "확인", style: .default) { _ in
                // 로그아웃 처리
                do {
                    
                    if Auth.auth().currentUser?.providerData.first?.providerID == "google.com" {
                        try Auth.auth().signOut()
                    } else {
                        UserApi.shared.logout { error in
                            if let error = error {
                                print("로그아웃 실패: \(error)")
                            } else {
                                print("logout() 성공")
                            }
                        }
                    }
                    
                    if let sceneDelegate = UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate,
                       let window = sceneDelegate.window {
                        let storyboard = UIStoryboard(name: "Main", bundle: nil)
                        let loginVC = storyboard.instantiateViewController(withIdentifier: "LoginVC") as? LoginViewController
                        window.rootViewController = loginVC
                        window.makeKeyAndVisible()
                    }
                    
                } catch {
                    
                    print("로그아웃 실패: \(error.localizedDescription)")
                    
                }
            }
            alert.addAction(okAction)
            
            if let sceneDelegate = UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate,
               let window = sceneDelegate.window {
                window.rootViewController?.present(alert, animated: true)
            }
            
        }
        
    }
    
}
