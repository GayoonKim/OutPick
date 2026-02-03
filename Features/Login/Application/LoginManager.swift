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

    // DI를 위한 이니셜라이저(테스트/스테이징에서 Mock 주입 가능)
    // - 참고: 운영 코드에서는 `LoginManager.shared`만 사용하면 됩니다.
    init(authRepository: SocialAuthRepositoryProtocol = DefaultSocialAuthRepository()) {
        self.authRepository = authRepository
    }

    private var userEmail: String = ""
    private(set) var currentUserProfile: UserProfile?

    var deviceIDListener: ListenerRegistration?

    /// 강제 로그아웃이 필요할 때 AppCoordinator로 라우팅을 위임하기 위한 콜백
    /// - 참고: AppCoordinator에서 주입합니다.
    var onForceLogout: (() -> Void)?

    // MARK: - 중복 로그인 리스너 상태
    // Firestore 리스너는 attach 직후(캐시 → 서버) 여러 번 호출될 수 있어요.
    // 최소 1번이라도 remote deviceID == 내 deviceID를 확인한 뒤에만(활성화 상태 이후) 강제 로그아웃을 수행합니다.
    private var hasSeenOwnDeviceID: Bool = false
    private var didHandleKick: Bool = false

    // 중복 로그인 Alert가 떠있는 동안 재진입 방지
    private var isPresentingDuplicateAlert: Bool = false

    // onForceLogout 콜백은 어떤 경로로든 "최대 1회"만 호출되도록 보장
    private var didInvokeForceLogoutCallback: Bool = false

    var getUserEmail: String { userEmail }

    func setUserEmail(_ email: String) {
        self.userEmail = email
    }

    func setCurrentUserProfile(_ profile: UserProfile?) {
        self.currentUserProfile = profile
    }

    // MARK: - 자동 로그인 체크

    private let authRepository: SocialAuthRepositoryProtocol

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

    // MARK: - 프로필

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

    // MARK: - 중복 로그인

    /// 새 기기 로그인 시, Users/{email}.deviceID를 무조건 내 deviceID로 덮어쓴다.
    /// 기존 기기는 리스너가 감지해서 로그아웃된다.
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
        self.isPresentingDuplicateAlert = false
        self.didInvokeForceLogoutCallback = false

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

            // 1) remote가 내 deviceID와 일치하면 "활성화 상태"(이후부터 불일치면 킥 처리)
            if remote == currentDeviceID {
                self.hasSeenOwnDeviceID = true
                return
            }

            // 2) attach 직후(캐시 → 서버) 초기 스냅샷에서 불일치가 먼저 올 수 있어요.
            // remote == local을 1번이라도 확인하기 전까지는 불일치를 무시해서 "새 기기"에서의 자기 킥을 방지합니다.
            if self.hasSeenOwnDeviceID == false {
                return
            }

            // 3) 활성화 상태 이후 불일치가 오면 다른 기기 로그인으로 킥된 것으로 판단
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
        // Alert 표시 중이면 중복 표시/상태 꼬임 방지
        if isPresentingDuplicateAlert { return }
        isPresentingDuplicateAlert = true

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

        // 콜백 재사용을 위해 플래그 초기화
        self.didInvokeForceLogoutCallback = false

        // 어떤 경로로든(즉시 호출/타임아웃/Kakao completion) onForceLogout는 최대 1회만 실행
        // 비동기 큐/타이머에서 늦게 실행돼도 self가 해제되면 아무 일도 하지 않도록 약한 참조로 보수적으로 캡처
        let invokeForceLogoutOnce: () -> Void = { [weak self] in
            guard let self else { return }
            if self.didInvokeForceLogoutCallback { return }
            self.didInvokeForceLogoutCallback = true

            // 강제 로그아웃 라우팅이 확정되는 시점에 Alert 재진입 방지 플래그도 정리
            self.isPresentingDuplicateAlert = false

            self.onForceLogout?()
        }

        // 캐시 삭제
        // KeychainManager 삭제 메서드 이름이 프로젝트마다 다를 수 있음
        KeychainManager.shared.delete(service: "GayoonKim.OutPick", account: "UserProfile")

        // Firebase/Google 로그아웃
        do { try Auth.auth().signOut() } catch { print("Firebase signOut error: \(error)") }
        GIDSignIn.sharedInstance.signOut()

        // UX/루트 라우팅은 외부 SDK completion에 묶지 않고 즉시 보장
        DispatchQueue.main.async {
            invokeForceLogoutOnce()
        }

        // 안전망(1초) — Kakao logout completion이 오지 않아도 라우팅이 보장되도록
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            invokeForceLogoutOnce()
        }

        // Kakao 로그아웃 (토큰 없어도 에러 무시)
        UserApi.shared.logout { error in
            if let error { print("Kakao logout error: \(error)") }

            DispatchQueue.main.async {
                invokeForceLogoutOnce()
            }
        }
    }
}
