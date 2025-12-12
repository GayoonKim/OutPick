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
    
    // 중복 로그인 탐지
    func setupDevIDListener() async throws {
        print("🔄🔄🔄🔄🔄 setupDevIDListener 호출")

        // 기존 리스너 제거 후 재등록
        deviceIDListener?.remove()
        deviceIDListener = nil

        let email = self.getUserEmail
        guard !email.isEmpty else {
            print("⚠️ setupDevIDListener: userEmail 비어있음")
            return
        }

        let currentDeviceID = await UIDevice.persistentDeviceID
        let userRef = FirebaseManager.shared.db.collection("Users").document(email)

        deviceIDListener = userRef.addSnapshotListener({ [weak self] documentSnapshot, error in
            guard let self = self else { return }

            if let error = error {
                print("사용자 문서 불러오기 실패: \(error.localizedDescription)")
                return
            }

            guard let document = documentSnapshot else { return }
            let remoteDeviceID = document.get("deviceID") as? String

            // 초기 상태: deviceID 가 없으면 내 값으로 초기화 (선택적)
            if remoteDeviceID == nil || (remoteDeviceID?.isEmpty == true) {
                Task {
                    do {
                        try await userRef.updateData(["deviceID": currentDeviceID])
                        print("ℹ️ deviceID 초기화 완료")
                    } catch {
                        print("⚠️ deviceID 초기화 실패: \(error)")
                    }
                }
                return
            }

            // 다른 기기에서 로그인 감지
            if remoteDeviceID != currentDeviceID {
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

        let device_id = await UIDevice.persistentDeviceID
        let email = self.getUserEmail
        guard !email.isEmpty else {
            print("⚠️ updateLogDevID: userEmail 비어있음")
            return
        }

        let userRef = FirebaseManager.shared.db.collection("Users").document(email)

        do {
            let resultAny = try await FirebaseManager.shared.db.runTransaction({ (txn, errorPointer) -> Any? in
                do {
                    let snap = try txn.getDocument(userRef)
                    let savedDeviceID = snap.get("deviceID") as? String

                    // 비어있거나 이미 내 값이면 set/update, 다른 기기 값이면 덮어쓰지 않음
                    if savedDeviceID == nil || savedDeviceID == device_id {
                        txn.updateData(["deviceID": device_id], forDocument: userRef)
                        return NSNumber(value: true)
                    } else {
                        return NSNumber(value: false)
                    }
                } catch {
                    // 트랜잭션 블록은 throw 할 수 없으므로 NSErrorPointer로 전달
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            })
            let updated: Bool = (resultAny as? NSNumber)?.boolValue ?? false
            print("로그인 기기 ID 변경 트랜잭션 완료, updated=\(updated)")
        } catch {
            print("로그인 기기 ID 변경 실패(tx): \(error)")
        }

        // 리스너 보장
        try await self.setupDevIDListener()
        print("🔄🔄🔄🔄🔄 updateLogDevID 호출 끝")
    }
    
//    func startUserProfileListener(email: String) {
//        userProfileListener?.remove()
//        userProfileListener = nil
//
//        userProfileListener = FirebaseManager.shared.listenToUserProfile(email: email) { [weak self] result in
//            guard let self = self else { return }
//            switch result {
//            case .success(let profile):
//                self.currentUserProfile = profile
//                if let data = try? JSONEncoder().encode(profile) {
//                    KeychainManager.shared.save(data, service: "GayoonKim.OutPick", account: "UserProfile")
//                }
//                
//                Task { await FirebaseManager.shared.joinedRoomStore.replace(with: profile.joinedRooms) }
//                print("🔄 프로필 갱신: \(profile)")
//            case .failure(let error):
//                print("❌ 프로필 리스너 에러: \(error)")
//            }
//        }
//    }
    
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
