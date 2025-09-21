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
import FirebaseFirestore

class LoginManager {
    
    static let shared = LoginManager()
    
    private var userEmail: String = ""
    
    var getUserEmail: String {
        return userEmail
    }
    
    var deviceIDListener: ListenerRegistration?
    
    private(set) var currentUserProfile: UserProfile?
    var userProfile: UserProfile? {
        return currentUserProfile
    }
    
    func setCurrentUserProfile(_ profile: UserProfile?) {
        self.currentUserProfile = profile
    }
    
    // 중복 로그인 탐지
    func setupDevIDListener() async throws{
        do {
            guard let userDoc = try await FirebaseManager.shared.getUserDoc() else { return }
            deviceIDListener = userDoc.reference.addSnapshotListener({ [weak self] documentSnapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("사용자 문서 불러오기 실패: \(error.localizedDescription)")
                    return
                }
                
                guard let document = documentSnapshot,
                      let deviceID = document.data()?["deviceID"] as? String else {
                    return
                }
                
                // 다른 기기에서 로그인 감지
                if deviceID != UIDevice.current.identifierForVendor?.uuidString {
                    DispatchQueue.main.async {
                        AlertManager.showDuplicateLoginAlert()
                        self.deviceIDListener?.remove()
                        self.deviceIDListener = nil
                    }
                }
            })
        } catch {
            print("기기 ID 리스너 설정 실패: \(error.localizedDescription)")
        }
    }
    
    // 중복 로그인 방지를 위한 로그인 기기 ID 변경
    func updateLogDevID() async throws {
        print("updateLogDevID 호출")
        
        do {
            let device_id = await UIDevice.current.identifierForVendor?.uuidString ?? "Unknown_User"
            guard let user_doc = try await FirebaseManager.shared.getUserDoc() else { return }
            
            if let savedDeviceID = user_doc.get("deviceID") as? String,
               savedDeviceID == self.currentUserProfile?.deviceID {
                print("이전과 동일한 기기")
                return
            }
            
            let _ = try await FirebaseManager.shared.db.runTransaction({ (transaction, errorPointer) -> Any? in
                transaction.updateData(["deviceID": device_id], forDocument: user_doc.reference)
                
                return nil
            })
            
            print("로그인 기기 ID 변경")
        } catch {
            print("로그인 기기 ID 변경 실패: \(error)")
        }
    }
    
    // Firestore에서 사용자 이메일로 만들어진 프로필 문서 쿼리
    func fetchUserProfileFromKeychain(completion: @escaping (UIViewController) -> Void) {
        print("fetchUserProfileFromKeychain 호출")

        if let data = KeychainManager.shared.read(service: "GayoonKim.OutPick", account: "UserProfile"),
           let userProfile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.currentUserProfile = userProfile
            
            Task {
                try await self.updateLogDevID()
                try await self.setupDevIDListener()
            }
            
//            let mainStorybard = UIStoryboard(name: "Main", bundle: nil)
//            let initialViewControlle = mainStorybard.instantiateViewController(withIdentifier: "weatherVC")
            let customTabBarVC = CustomTabBarViewController()
            completion(customTabBarVC)
        } else {
            Task {
                let vc = try await fetchProfileFromFirebase(LoginManager.shared.getUserEmail)
                completion(vc)
            }
        }
    }
    
    func fetchProfileFromFirebase(_ email: String) async throws -> UIViewController {
        do {
            let profile = try await FirebaseManager.shared.fetchUserProfileFromFirestore(email: email)
            self.currentUserProfile = profile
            if let data = try? JSONEncoder().encode(profile) {
                KeychainManager.shared.save(data, service: "GayoonKim.OutPick", account: "UserProfile")
            }
            
            try await updateLogDevID()
            try await setupDevIDListener()
            
            return await MainActor.run {
//                let mainStorybard = UIStoryboard(name: "Main", bundle: nil)
//                return mainStorybard.instantiateViewController(withIdentifier: "weatherVC")
                let customTabBarVC = CustomTabBarViewController()
                return customTabBarVC
            }
            
        } catch {
            
            print("\(email) 사용자 프로필 불러오기 실패: \(error.localizedDescription)")
            return await MainActor.run {
                let mainStorybard = UIStoryboard(name: "Main", bundle: nil)
                return mainStorybard.instantiateViewController(withIdentifier: "ProfileNav")
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
