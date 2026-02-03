//
//  LoginManager.swift
//  OutPick
//
//  Created by 김가윤 on 10/29/24.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import GoogleSignIn
import KakaoSDKUser

final class LoginManager {

    static let shared = LoginManager()
    private init() {}

    private var userEmail: String = ""
    private(set) var currentUserProfile: UserProfile?

    var deviceIDListener: ListenerRegistration?

    // MARK: - Duplicate login listener state
    // Firestore listener can fire multiple times on attach (cache -> server). We only kick after we've
    // confirmed at least once that remote deviceID == current deviceID.
    private var hasSeenOwnDeviceID: Bool = false
    private var didHandleKick: Bool = false

    var getUserEmail: String { userEmail }

    func setUserEmail(_ email: String) {
        self.userEmail = email
    }

    func setCurrentUserProfile(_ profile: UserProfile?) {
        self.currentUserProfile = profile
    }

    // MARK: - Notifications
    static let forceLogoutNotification = Notification.Name("OutPick.forceLogout")

    // MARK: - Auto login check (이미 repo로 이동한 버전 가정)
    // 확실하지 않음: authRepository / restore 메서드는 네 프로젝트 구현에 맞춰 유지
    private let authRepository: SocialAuthRepositoryProtocol = DefaultSocialAuthRepository()

    func checkExistingLogin() async -> Bool {
        if let email = await authRepository.restoreGoogleEmailIfLoggedIn() {
            setUserEmail(email)
            return true
        }
        if let email = await authRepository.restoreKakaoEmailIfLoggedIn() {
            setUserEmail(email)
            return true
        }
        return false
    }

    // MARK: - Profile
    func loadUserProfile() async -> Result<UserProfile, Error> {
        if let data = KeychainManager.shared.read(service: "GayoonKim.OutPick", account: "UserProfile"),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.currentUserProfile = profile
            return .success(profile)
        }

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

    // MARK: - Duplicate login (Option 2: new device wins)

    /// ✅ 새 기기 로그인 시, Users/{email}.deviceID를 무조건 내 deviceID로 덮어쓴다.
    /// 기존 기기는 리스너가 감지해서 킥(로그아웃)된다.
    func updateLogDevID() async throws {
        let deviceID = await UIDevice.persistentDeviceID
        let email = self.getUserEmail
        guard !email.isEmpty else { return }

        let userRef = FirebaseManager.shared.db.collection("Users").document(email)

        _ = try await FirebaseManager.shared.db.runTransaction { txn, errorPointer -> Any? in
            do {
                let snap = try txn.getDocument(userRef)

                if snap.exists {
                    txn.updateData([
                        "deviceID": deviceID,
                        "lastLoginAt": FieldValue.serverTimestamp()
                    ], forDocument: userRef)
                } else {
                    txn.setData([
                        "deviceID": deviceID,
                        "lastLoginAt": FieldValue.serverTimestamp()
                    ], forDocument: userRef, merge: true)
                }
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        // 덮어쓰기 성공 후에만 리스너를 붙인다
        try await setupDevIDListener()
    }

    func setupDevIDListener() async throws {
        deviceIDListener?.remove()
        deviceIDListener = nil

        let email = self.getUserEmail
        guard !email.isEmpty else { return }

        let currentDeviceID = await UIDevice.persistentDeviceID
        self.hasSeenOwnDeviceID = false
        self.didHandleKick = false
        let userRef = FirebaseManager.shared.db.collection("Users").document(email)

        deviceIDListener = userRef.addSnapshotListener { [weak self] snap, error in
            guard let self else { return }
            if let error {
                print("deviceID 리스너 오류: \(error.localizedDescription)")
                return
            }
            guard let snap else { return }

            let remoteDeviceID = snap.get("deviceID") as? String
            guard let remote = remoteDeviceID, remote.isEmpty == false else { return }

            // 1) First, if it matches our deviceID, we are fully "armed".
            if remote == currentDeviceID {
                self.hasSeenOwnDeviceID = true
                return
            }

            // 2) Listener can fire cache -> server right after attaching. Until we have confirmed once
            // that remote == local, ignore mismatches to avoid self-kick on the new device.
            if self.hasSeenOwnDeviceID == false {
                // Optional: If you want to be stricter, you can only ignore cache snapshots.
                // Here we ignore any mismatch before first match, which is safer for UX.
                return
            }

            // 3) After we're armed, any mismatch means we were kicked by another device.
            if self.didHandleKick { return }
            self.didHandleKick = true

            Task { @MainActor in
                self.handleKickedByAnotherDevice()
            }
        }
    }

    // MARK: - 중복 로그인 로그아웃 처리

    @MainActor
    private func handleKickedByAnotherDevice() {
        didHandleKick = true
        // 중복 호출 방지
        deviceIDListener?.remove()
        deviceIDListener = nil

        AlertManager.showDuplicateLoginAlert { [weak self] in
            guard let self else { return }
            self.clearSessionAndNotifyForceLogout()
        }
    }

    private func clearSessionAndNotifyForceLogout() {
        // 세션 정리
        self.userEmail = ""
        self.currentUserProfile = nil

        // 캐시 삭제
        // KeychainManager 삭제 메서드 이름이 프로젝트마다 다를 수 있음
        KeychainManager.shared.delete(service: "GayoonKim.OutPick", account: "UserProfile")

        // Firebase/Google 로그아웃
        do { try Auth.auth().signOut() } catch { print("Firebase signOut error: \(error)") }
        GIDSignIn.sharedInstance.signOut()

        // Kakao 로그아웃 (토큰 없어도 에러 무시)
        UserApi.shared.logout { error in
            if let error { print("Kakao logout error: \(error)") }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: LoginManager.forceLogoutNotification, object: nil)
            }
        }
    }
}
