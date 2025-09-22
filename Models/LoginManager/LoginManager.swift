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
    private var userProfileListener: ListenerRegistration?
    
    private(set) var currentUserProfile: UserProfile?
    var userProfile: UserProfile? {
        return currentUserProfile
    }
    
    func setCurrentUserProfile(_ profile: UserProfile?) {
        self.currentUserProfile = profile
    }
    
    func startUserProfileListener(email: String) {
        userProfileListener?.remove()
        userProfileListener = nil

        userProfileListener = FirebaseManager.shared.listenToUserProfile(email: email) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let profile):
                self.currentUserProfile = profile
                if let data = try? JSONEncoder().encode(profile) {
                    KeychainManager.shared.save(data, service: "GayoonKim.OutPick", account: "UserProfile")
                }
                print("🔄 프로필 갱신: \(profile)")
            case .failure(let error):
                print("❌ 프로필 리스너 에러: \(error)")
            }
        }
    }
    
    // 중복 로그인 탐지
    func setupDevIDListener() async throws {
        print("🔄🔄🔄🔄🔄 setupDevIDListener 호출")
        let userRef = FirebaseManager.shared.db.collection("Users").document(self.getUserEmail)
        deviceIDListener = userRef.addSnapshotListener({ [weak self] documentSnapshot, error in
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
            if deviceID != UIDevice.persistentDeviceID {
                DispatchQueue.main.async {
                    AlertManager.showDuplicateLoginAlert()
                    self.deviceIDListener?.remove()
                    self.deviceIDListener = nil
                }
            }
        })
        
        print("🔄🔄🔄🔄🔄 setupDevIDListener 호출 끝")
    }
    
    // 중복 로그인 방지를 위한 로그인 기기 ID 변경
    func updateLogDevID() async throws {
        print("🔄🔄🔄🔄🔄 1. updateLogDevID 호출")
        
        do {
            
            let device_id = await UIDevice.persistentDeviceID
            print("🔄🔄🔄🔄🔄 2. deviceID", device_id)
            let userRef = FirebaseManager.shared.db.collection("Users").document(self.getUserEmail)
            print("🔄🔄🔄🔄🔄 3. userRef", userRef)
            
            
            let document = try await userRef.getDocument()
            if let savedDeviceID = document.get("deviceID") as? String,
               savedDeviceID == device_id {
                print("이전과 동일한 기기")
                return
            }
            
            try await userRef.updateData(["deviceID": device_id])
            
            print("로그인 기기 ID 변경")
//            try await self.setupDevIDListener()
            print("🔄🔄🔄🔄🔄 updateLogDevID 호출 끝")
        } catch {
            print("로그인 기기 ID 변경 실패: \(error)")
        }
        
        try await self.setupDevIDListener()
    }
    
    func loadUserProfile() async -> Result<UserProfile, Error> {
        // Try to load from Keychain
        if let data = KeychainManager.shared.read(service: "GayoonKim.OutPick", account: "UserProfile"),
           let userProfile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.currentUserProfile = userProfile
            return .success(userProfile)
        }
        // Keychain not found or decode failed, fetch from Firebase
        do {
            let email = self.getUserEmail
            let profile = try await FirebaseManager.shared.fetchUserProfileFromFirestore(email: email)
            self.currentUserProfile = profile
            if let data = try? JSONEncoder().encode(profile) {
                KeychainManager.shared.save(data, service: "GayoonKim.OutPick", account: "UserProfile")
            }
            return .success(profile)
        } catch {
            return .failure(error)
        }
    }
    
    func makeInitialViewController() async throws -> UIViewController {
        let result = await loadUserProfile()
        switch result {
        case .success:
            try await self.updateLogDevID()
//            try await self.setupDevIDListener()
            return await MainActor.run {
                CustomTabBarViewController()
            }
        case .failure(let error):
            print("\(self.getUserEmail) 사용자 프로필 불러오기 실패: \(error.localizedDescription)")
            return await MainActor.run {
                let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
                return mainStoryboard.instantiateViewController(withIdentifier: "ProfileNav")
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

extension UIDevice {
    static var persistentDeviceID: String {
        if let saved = KeychainManager.shared.read(service: "OutPick", account: "PersistentDeviceID"),
           let id = String(data: saved, encoding: .utf8) {
            return id
        }
        let newID = UUID().uuidString
        KeychainManager.shared.save(Data(newID.utf8), service: "OutPick", account: "PersistentDeviceID")
        return newID
    }
}
