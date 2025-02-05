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
        
        print("fetchUserProfile 호출")

        FirebaseManager.shared.fetchUserProfileFromFirestore(email: email) { result in
            DispatchQueue.main.async {
                
                let initialViewControlle: UIViewController
                
                switch result {
                case .success(let userProfile):
                    print("프로필 불러오기 성공")

                    let mainStorybard = UIStoryboard(name: "Main", bundle: nil)
                    initialViewControlle = mainStorybard.instantiateViewController(withIdentifier: "HomeTBC")
                    print(initialViewControlle)
                    completion(initialViewControlle)
                case .failure(let error):
                    print("Failed to fetch user profile: \(error.localizedDescription)")

                    let mainStorybard = UIStoryboard(name: "Main", bundle: nil)
                    initialViewControlle = mainStorybard.instantiateViewController(withIdentifier: "ProfileNav")
                    print(initialViewControlle)
                    completion(initialViewControlle)
                }
                
            }
        }

    }
    
    // 카카오 사용자 이메일 불러오기
    func getKakaoEmail(completion: @escaping (Bool) -> Void) {
        UserApi.shared.me() {(user, error) in
            if let error = error {
                print(error)
//                completion(nil)
            } else {
                print("me() 성공")
                
                // 사용자 이메일로 프로필 설정 여부 확인
                guard let userEmail = user?.kakaoAccount?.email else {
                    completion(false)
                    return
                }
                
                self.userEmail = userEmail
                completion(true)
            }
        }
    }
    
    // 구글 사용자 이메일 불러오기
    func getGoogleEmail(completion: @escaping (Bool) -> Void) {
        guard let userEmail = Auth.auth().currentUser?.email else {
            completion(false)
            return
        }
        
        self.userEmail = userEmail
        completion(true)
    }
    
}
