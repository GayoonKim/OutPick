//
//  KakaoLoginManager.swift
//  OutPick
//
//  Created by 김가윤 on 10/29/24.
//

import UIKit
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser
import FirebaseCore
import FirebaseAuth

class LoginManager {
    
    static let shared = LoginManager()
    
    private var userEmail: String = ""
    
    var getUserEmail: String {
        return userEmail
    }
    
    // Firestore에서 사용자 이메일로 만들어진 프로필 문서 쿼리
    func fetchUserProfile(_ email: String, completion: @escaping (UIViewController) -> Void) {
        FirestoreManager.shared.fetchUserProfileFromFirestore(email: email) { result in
            let initialViewControlle: UIViewController
            
            switch result {
            case .success(let userProfile):
                print("User Profile: \(userProfile)")
                UserProfile.sharedUserProfile = userProfile

                let mainStorybard = UIStoryboard(name: "Main", bundle: nil)
                initialViewControlle = mainStorybard.instantiateViewController(withIdentifier: "HomeTBC")
                completion(initialViewControlle)
            case .failure(let error):
                print("Failed to fetch user profile: \(error.localizedDescription)")

                let mainStorybard = UIStoryboard(name: "Main", bundle: nil)
                initialViewControlle = mainStorybard.instantiateViewController(withIdentifier: "FirstProfileVC")
                completion(initialViewControlle)
            }
        }
    }
    
    // 카카오 사용자 이메일 불러오기
    func getKakaoEmail(completion: @escaping (String?) -> Void) {
        UserApi.shared.me() {(user, error) in
            if let error = error {
                print(error)
                completion(nil)
            } else {
                print("me() 성공")
                
                // 사용자 이메일로 프로필 설정 여부 확인
                guard let userEmail = user?.kakaoAccount?.email else {
                    completion(nil)
                    return
                }
                self.userEmail = userEmail
                completion(userEmail)
            }
        }
    }
    
    // 구글 사용자 이메일 불러오기
    func getGoogleEmail(completion: @escaping (String?) -> Void) {
        guard let userEmail = Auth.auth().currentUser?.email else {
            completion(nil)
            return
        }
        
        self.userEmail = userEmail
        completion(userEmail)
    }
    
}
