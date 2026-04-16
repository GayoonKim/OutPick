//
//  UserProfileRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine
import FirebaseFirestore

final class UserProfileRepository: UserProfileRepositoryProtocol {
    private let db: Firestore
    private let usersCollection = "users"
    private let userIdentitiesCollection = "userIdentities"
    
    // users/{userDocumentID} 또는 users(email query) 프로필 스냅샷 리스너 캐시
    private var userProfileListeners: [String: ListenerRegistration] = [:]
    // 프로필 변경 스트림(Combine)
    private var userProfileSubjects: [String: PassthroughSubject<UserProfile, Error>] = [:]
    // 현재 사용자 프로필 갱신 훅(email key -> handler)
    private var currentUserProfileHandlers: [String: (UserProfile) -> Void] = [:]
    
    init(db: Firestore) {
        self.db = db
    }
    
    deinit {
        // 모든 리스너 정리
        userProfileListeners.values.forEach { $0.remove() }
        userProfileSubjects.values.forEach { $0.send(completion: .finished) }
        currentUserProfileHandlers.removeAll()
    }

    private func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func currentUserDocumentID() -> String {
        LoginManager.shared.getUserDocumentID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentUserDocumentRef() -> DocumentReference? {
        let userDocumentID = currentUserDocumentID()
        guard !userDocumentID.isEmpty else { return nil }
        return db.collection(usersCollection).document(userDocumentID)
    }

    private func decodeProfile(_ data: [String: Any], emailFallback: String) -> UserProfile {
        let dto = UserProfileFirestoreCodec.fromDocument(data, emailFallback: emailFallback)
        return UserProfileMapper.toDomain(dto)
    }

    private func hasRequiredProfileData(_ data: [String: Any]) -> Bool {
        guard let nickname = data["nickname"] as? String else { return false }
        return !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func findProfileDocByEmail(normalizedEmail: String) async throws -> QueryDocumentSnapshot? {
        let query = db.collection(usersCollection)
            .whereField("email", isEqualTo: normalizedEmail)
            .limit(to: 10)
        let snap = try await query.getDocuments()
        return snap.documents.first(where: { hasRequiredProfileData($0.data()) }) ?? snap.documents.first
    }

    private func fetchProfileByEmail(normalizedEmail: String) async throws -> UserProfile? {
        let doc = try await findProfileDocByEmail(normalizedEmail: normalizedEmail)
        guard let doc else { return nil }
        return decodeProfile(doc.data(), emailFallback: normalizedEmail)
    }

    func resolveOrCreateUserDocumentID(authenticatedUser: AuthenticatedUser) async throws -> String {
        let normalizedIdentityKey = authenticatedUser.identityKey
        guard !normalizedIdentityKey.isEmpty, !authenticatedUser.providerUserID.isEmpty else {
            throw FirebaseError.FailedToFetchProfile
        }

        let normalizedEmail = normalizeEmail(authenticatedUser.email ?? "")
        let identityRef = db.collection(userIdentitiesCollection).document(normalizedIdentityKey)

        let identitySnap = try await identityRef.getDocument()
        if let mappedID = identitySnap.get("userDocumentID") as? String,
           !mappedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let userDocumentID = mappedID.trimmingCharacters(in: .whitespacesAndNewlines)
            let userRef = db.collection(usersCollection).document(userDocumentID)
            let batch = db.batch()
            batch.setData([
                "identityKey": normalizedIdentityKey,
                "provider": authenticatedUser.provider.rawValue,
                "providerUserID": authenticatedUser.providerUserID,
                "email": normalizedEmail,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: userRef, merge: true)
            batch.setData([
                "userDocumentID": userDocumentID,
                "provider": authenticatedUser.provider.rawValue,
                "providerUserID": authenticatedUser.providerUserID,
                "email": normalizedEmail,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: identityRef, merge: true)
            try await batch.commit()
            return userDocumentID
        }

        let userDocumentID = db.collection(usersCollection).document().documentID
        let userRef = db.collection(usersCollection).document(userDocumentID)

        let batch = db.batch()
        batch.setData([
            "userDocumentID": userDocumentID,
            "provider": authenticatedUser.provider.rawValue,
            "providerUserID": authenticatedUser.providerUserID,
            "email": normalizedEmail,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: identityRef, merge: true)
        batch.setData([
            "identityKey": normalizedIdentityKey,
            "provider": authenticatedUser.provider.rawValue,
            "providerUserID": authenticatedUser.providerUserID,
            "email": normalizedEmail,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: userRef, merge: true)
        try await batch.commit()

        return userDocumentID
    }

    func listenToCurrentUserProfile(onCurrentUserProfileUpdated: ((UserProfile) -> Void)? = nil) {
        guard let docRef = currentUserDocumentRef() else { return }
        let userDocumentID = docRef.documentID
        let key = "current:\(userDocumentID)"

        if let onCurrentUserProfileUpdated {
            currentUserProfileHandlers[key] = onCurrentUserProfileUpdated
        }
        if userProfileListeners[key] != nil { return }

        let subject: PassthroughSubject<UserProfile, Error>
        if let s = userProfileSubjects[key] {
            subject = s
        } else {
            let s = PassthroughSubject<UserProfile, Error>()
            userProfileSubjects[key] = s
            subject = s
        }

        let listener = docRef.addSnapshotListener { snapshot, error in
            if let error {
                subject.send(completion: .failure(error))
                return
            }
            guard let snapshot, snapshot.exists, let data = snapshot.data(), self.hasRequiredProfileData(data) else {
                return
            }

            let profile = self.decodeProfile(
                data,
                emailFallback: LoginManager.shared.getUserEmail
            )
            Task { @MainActor in
                LoginManager.shared.setCurrentUserProfile(profile)
            }
            self.currentUserProfileHandlers[key]?(profile)
            subject.send(profile)
        }

        userProfileListeners[key] = listener
    }
    
    func listenToUserProfile(email: String, onCurrentUserProfileUpdated: ((UserProfile) -> Void)? = nil) {
        let key = normalizeEmail(email)
        guard !key.isEmpty else { return }
        if let onCurrentUserProfileUpdated {
            currentUserProfileHandlers[key] = onCurrentUserProfileUpdated
        }
        if let _ = userProfileListeners[key] { return }
        
        // subject 없으면 생성
        let subject: PassthroughSubject<UserProfile, Error>
        if let s = userProfileSubjects[key] {
            subject = s
        } else {
            let s = PassthroughSubject<UserProfile, Error>()
            userProfileSubjects[key] = s
            subject = s
        }

        let query = db.collection(usersCollection)
            .whereField("email", isEqualTo: key)
            .limit(to: 10)
        let listener = query.addSnapshotListener { snapshot, error in
            if let error = error {
                subject.send(completion: .failure(error))
                return
            }
            let doc = snapshot?.documents.first(where: { self.hasRequiredProfileData($0.data()) })
                ?? snapshot?.documents.first
            guard let doc else { return }
            let profile = self.decodeProfile(doc.data(), emailFallback: key)
            subject.send(profile)
        }

        userProfileListeners[key] = listener
        print(#function, "프로필 실시간 리스너 설정 갱신", userProfileListeners)
    }
    
    func userProfilePublisher(email: String) -> AnyPublisher<UserProfile, Error> {
        let key = normalizeEmail(email)
        guard !key.isEmpty else {
            return Fail(error: FirebaseError.FailedToFetchProfile).eraseToAnyPublisher()
        }

        // 1) subject 없으면 생성/캐시
        let subject: PassthroughSubject<UserProfile, Error>
        if let s = userProfileSubjects[key] {
            subject = s
        } else {
            let s = PassthroughSubject<UserProfile, Error>()
            userProfileSubjects[key] = s
            subject = s
        }
        
        // 2) 리스너 없으면 시작
        if userProfileListeners[key] == nil {
            listenToUserProfile(email: key)
        }
        
        // 3) 외부에는 Publisher로만 노출
        return subject.eraseToAnyPublisher()
    }
    
    func stopListenUserProfile(email: String) {
        let key = normalizeEmail(email)
        guard !key.isEmpty else { return }

        if let listener = userProfileListeners[key] {
            listener.remove()
            userProfileListeners.removeValue(forKey: key)
        }
        
        if let subject = userProfileSubjects[key] {
            subject.send(completion: .finished)
            userProfileSubjects.removeValue(forKey: key)
        }
        currentUserProfileHandlers.removeValue(forKey: key)
    }
    
    func saveCurrentUserProfile() async throws {
        do {
            guard let profile = LoginManager.shared.currentUserProfile else {
                throw FirebaseError.FailedToSaveProfile
            }
            let userDocumentID = try await LoginManager.shared.ensureUserDocumentID()
            guard !userDocumentID.isEmpty else {
                throw FirebaseError.FailedToSaveProfile
            }

            // Domain -> DTO -> Firestore 문서
            let dto = UserProfileMapper.toDTO(profile)
            var profileData = UserProfileFirestoreCodec.toDocument(dto)
            profileData["email"] = normalizeEmail(LoginManager.shared.getUserEmail)
            if let authenticatedUser = LoginManager.shared.authenticatedUser {
                profileData["identityKey"] = authenticatedUser.identityKey
                profileData["provider"] = authenticatedUser.provider.rawValue
                profileData["providerUserID"] = authenticatedUser.providerUserID
            }

            // createdAt은 서버 기준으로 저장(정렬/쿼리에 유리)
            profileData["createdAt"] = FieldValue.serverTimestamp()
            profileData["updatedAt"] = FieldValue.serverTimestamp()

            try await db.collection(usersCollection).document(userDocumentID).setData(profileData, merge: true)
        } catch {
            throw FirebaseError.FailedToSaveProfile
        }
    }

    func fetchCurrentUserProfile() async throws -> UserProfile {
        guard let docRef = currentUserDocumentRef() else {
            throw FirebaseError.FailedToFetchProfile
        }

        let snapshot = try await docRef.getDocument()
        guard let data = snapshot.data(), hasRequiredProfileData(data) else {
            throw FirebaseError.FailedToFetchProfile
        }

        return decodeProfile(data, emailFallback: LoginManager.shared.getUserEmail)
    }
    
    func fetchUserProfileFromFirestore(email: String) async throws -> UserProfile {
        print("fetchUserProfileFromFirestore 호출")
        let normalizedEmail = normalizeEmail(email)
        guard !normalizedEmail.isEmpty else {
            throw FirebaseError.FailedToFetchProfile
        }

        guard let fallbackProfile = try await fetchProfileByEmail(normalizedEmail: normalizedEmail) else {
            throw FirebaseError.FailedToFetchProfile
        }
        return fallbackProfile
    }
    
    func fetchUserProfiles(emails: [String]) async throws -> [UserProfile] {
        return try await withThrowingTaskGroup(of: UserProfile?.self) { group in
            for email in emails {
                group.addTask {
                    do {
                        let profile = try await self.fetchUserProfileFromFirestore(email: email)
                        return profile
                    } catch {
                        print("\(email) 사용자 프로필 불러오기 실패: \(error)")
                        return nil
                    }
                }
            }
            
            var profiles = [UserProfile]()
            for try await result in group {
                if let profile = result {
                    profiles.append(profile)
                }
            }
            
            return profiles
        }
    }
    
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String) async throws -> Bool {
        do {
            let query = db.collection(collectionName).whereField(fieldToCompare, isEqualTo: strToCompare)
            let snapshot = try await query.getDocuments()
            return !snapshot.isEmpty
        } catch {
            throw FirebaseError.Duplicate
        }
    }
    
    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws {
        guard !roomID.isEmpty, !userUID.isEmpty else { return }

        let stateRef = db.collection("users").document(userUID)
            .collection("roomStates").document(roomID)

        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let stateSnap = try transaction.getDocument(stateRef)

                let requested = max(Int64(0), lastReadSeq)
                let current = Self.toInt64(stateSnap.data()?["lastReadSeq"]) ?? 0
                let next = max(current, requested)

                guard next > current else { return nil }

                transaction.setData([
                    "lastReadSeq": next,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: stateRef, merge: true)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
    func fetchLastReadSeq(for roomID: String) async throws -> Int64 {
        let userDocumentID = currentUserDocumentID()
        guard !userDocumentID.isEmpty else { return 0 }

        let docRef = db.collection("users").document(userDocumentID)
            .collection("roomStates").document(roomID)
        
        let snap = try await docRef.getDocument()
        return Self.toInt64(snap.data()?["lastReadSeq"]) ?? 0
    }

    func upsertDeviceID(deviceID: String) async throws {
        let normalizedEmail = normalizeEmail(LoginManager.shared.getUserEmail)
        let userDocumentID: String
        if currentUserDocumentID().isEmpty {
            userDocumentID = try await LoginManager.shared.ensureUserDocumentID()
        } else {
            userDocumentID = currentUserDocumentID()
        }
        guard !userDocumentID.isEmpty else { return }

        let userRef = db.collection(usersCollection).document(userDocumentID)
        let sessionRef = userRef.collection("meta").document("session")
        let batch = db.batch()
        batch.setData([
            "email": normalizedEmail
        ], forDocument: userRef, merge: true)
        batch.setData([
            "deviceID": deviceID,
            "lastLoginAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: sessionRef, merge: true)
        try await batch.commit()
    }

    func listenToDeviceID(
        onUpdate: @escaping (String?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        let userDocumentID = currentUserDocumentID()
        guard !userDocumentID.isEmpty else {
            onUpdate(nil)
            return EmptyListenerRegistration()
        }

        let sessionRef = db.collection(usersCollection)
            .document(userDocumentID)
            .collection("meta")
            .document("session")

        return sessionRef.addSnapshotListener { snapshot, error in
            if let error {
                onError(error)
                return
            }
            onUpdate(snapshot?.get("deviceID") as? String)
        }
    }

    func upsertPushDevice(userDocumentID: String, state: PushDeviceState) async throws {
        let normalizedEmail = normalizeEmail(state.email)
        guard !userDocumentID.isEmpty, !state.deviceID.isEmpty else { return }

        let userRef = db.collection(usersCollection).document(userDocumentID)
        let deviceRef = userRef.collection("devices").document(state.deviceID)

        var payload: [String: Any] = [
            "deviceID": state.deviceID,
            "email": normalizedEmail,
            "platform": "ios",
            "pushEnabled": state.pushEnabled,
            "appState": state.appState.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let token = state.fcmToken, !token.isEmpty {
            payload["fcmToken"] = token
            payload["fcmTokenUpdatedAt"] = FieldValue.serverTimestamp()
        } else {
            payload["fcmToken"] = FieldValue.delete()
        }

        if let visibleRoomID = state.visibleRoomID, !visibleRoomID.isEmpty {
            payload["visibleRoomID"] = visibleRoomID
        } else {
            payload["visibleRoomID"] = FieldValue.delete()
        }

        if let socketID = state.socketID, !socketID.isEmpty {
            payload["socketId"] = socketID
        } else {
            payload["socketId"] = FieldValue.delete()
        }

        switch state.appState {
        case .foreground:
            payload["lastForegroundAt"] = FieldValue.serverTimestamp()
            payload["lastDisconnectAt"] = FieldValue.delete()
        case .background:
            payload["lastBackgroundAt"] = FieldValue.serverTimestamp()
        case .offline:
            payload["lastDisconnectAt"] = FieldValue.serverTimestamp()
        }

        let batch = db.batch()
        batch.setData([
            "email": normalizedEmail,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: userRef, merge: true)
        batch.setData(payload, forDocument: deviceRef, merge: true)
        try await batch.commit()
    }

    private static func toInt64(_ value: Any?) -> Int64? {
        switch value {
        case let intValue as Int:
            return Int64(intValue)
        case let int64Value as Int64:
            return int64Value
        case let number as NSNumber:
            return number.int64Value
        case let doubleValue as Double:
            return Int64(doubleValue)
        default:
            return nil
        }
    }
}

private final class EmptyListenerRegistration: NSObject, ListenerRegistration {
    func remove() {}
}
