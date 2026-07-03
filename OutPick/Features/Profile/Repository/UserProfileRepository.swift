//
//  UserProfileRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import FirebaseFirestore

final class UserProfileRepository: UserProfileRepositoryProtocol {
    private let db: Firestore
    private let usersCollection = "users"
    init(db: Firestore) {
        self.db = db
    }

    private func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeUserID(_ userID: String) -> String {
        userID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeProfile(_ data: [String: Any], emailFallback: String) -> UserProfile {
        let dto = UserProfileFirestoreCodec.fromDocument(data, emailFallback: emailFallback)
        return UserProfileMapper.toDomain(dto)
    }

    private func hasRequiredProfileData(_ data: [String: Any]) -> Bool {
        guard let nickname = data["nickname"] as? String else { return false }
        return !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resolveOrCreateUserDocumentID(authenticatedUser: AuthenticatedUser) async throws -> String {
        let normalizedIdentityKey = authenticatedUser.identityKey
        guard !normalizedIdentityKey.isEmpty, !authenticatedUser.providerUserID.isEmpty else {
            throw FirebaseError.FailedToFetchProfile
        }
        guard normalizedIdentityKey.contains("/") == false else {
            throw FirebaseError.FailedToFetchProfile
        }

        let normalizedEmail = normalizeEmail(authenticatedUser.email ?? "")
        let userDocumentID = normalizedIdentityKey
        let userRef = db.collection(usersCollection).document(userDocumentID)
        let userSnapshot = try await userRef.getDocument()

        var profileSeed: [String: Any] = [
            "userDocumentID": userDocumentID,
            "identityKey": normalizedIdentityKey,
            "provider": authenticatedUser.provider.rawValue,
            "providerUserID": authenticatedUser.providerUserID,
            "email": normalizedEmail,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if userSnapshot.exists == false {
            profileSeed["createdAt"] = FieldValue.serverTimestamp()
        }

        try await userRef.setData(profileSeed, merge: true)

        return userDocumentID
    }

    func saveCurrentUserProfile(
        _ profile: UserProfile,
        userID: String,
        email: String,
        authenticatedUser: AuthenticatedUser?
    ) async throws {
        do {
            let userDocumentID = normalizeUserID(userID)
            guard !userDocumentID.isEmpty else {
                throw FirebaseError.FailedToSaveProfile
            }

            // Domain -> DTO -> Firestore 문서
            let dto = UserProfileMapper.toDTO(profile)
            var profileData = UserProfileFirestoreCodec.toDocument(dto)
            profileData["userDocumentID"] = userDocumentID
            profileData["email"] = normalizeEmail(email)
            if let authenticatedUser {
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

    func fetchCurrentUserProfile(userID: String, emailFallback: String) async throws -> UserProfile {
        let userDocumentID = normalizeUserID(userID)
        guard !userDocumentID.isEmpty else {
            throw FirebaseError.FailedToFetchProfile
        }

        let docRef = db.collection(usersCollection).document(userDocumentID)
        let snapshot = try await docRef.getDocument()
        guard let data = snapshot.data(), hasRequiredProfileData(data) else {
            throw FirebaseError.FailedToFetchProfile
        }

        return decodeProfile(data, emailFallback: emailFallback)
    }
    
    func fetchUserProfile(userID: String) async throws -> UserProfile {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserID.isEmpty,
              normalizedUserID.contains("/") == false else {
            throw FirebaseError.FailedToFetchProfile
        }

        let snapshot = try await db.collection(usersCollection)
            .document(normalizedUserID)
            .getDocument()
        guard let data = snapshot.data(), hasRequiredProfileData(data) else {
            throw FirebaseError.FailedToFetchProfile
        }

        let emailFallback = (data["email"] as? String) ?? normalizedUserID
        return decodeProfile(data, emailFallback: emailFallback)
    }

    func fetchUserProfiles(userIDs: [String]) async throws -> [String: UserProfile] {
        let normalizedUserIDs = Array(
            Set(
                userIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.contains("/") }
            )
        )

        return try await withThrowingTaskGroup(of: (String, UserProfile)?.self) { group in
            for userID in normalizedUserIDs {
                group.addTask {
                    do {
                        let profile = try await self.fetchUserProfile(userID: userID)
                        return (userID, profile)
                    } catch {
                        print("\(userID) 사용자 프로필 불러오기 실패: \(error)")
                        return nil
                    }
                }
            }

            var profiles: [String: UserProfile] = [:]
            for try await result in group {
                if let (userID, profile) = result {
                    profiles[userID] = profile
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
        let trimmedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let userDocumentID = normalizeUserID(userUID)
        guard !trimmedRoomID.isEmpty, !userDocumentID.isEmpty else { return }

        let joinedRoomRef = db.collection("users").document(userDocumentID)
            .collection("joinedRooms").document(trimmedRoomID)

        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let joinedRoomSnap = try transaction.getDocument(joinedRoomRef)

                let requested = max(Int64(0), lastReadSeq)
                let current = Self.toInt64(joinedRoomSnap.data()?["lastReadSeq"]) ?? 0
                let next = max(current, requested)

                guard next > current else { return nil }

                transaction.setData([
                    "roomID": trimmedRoomID,
                    "lastReadSeq": next,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: joinedRoomRef, merge: true)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
    
    func fetchLastReadSeq(for roomID: String, userUID: String) async throws -> Int64 {
        let trimmedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let userDocumentID = normalizeUserID(userUID)
        guard !trimmedRoomID.isEmpty, !userDocumentID.isEmpty else { return 0 }

        let docRef = db.collection("users").document(userDocumentID)
            .collection("joinedRooms").document(trimmedRoomID)
        
        let snap = try await docRef.getDocument()
        return Self.toInt64(snap.data()?["lastReadSeq"]) ?? 0
    }

    func upsertDeviceID(userDocumentID: String, email: String, deviceID: String) async throws {
        let normalizedEmail = normalizeEmail(email)
        let normalizedUserDocumentID = normalizeUserID(userDocumentID)
        guard !normalizedUserDocumentID.isEmpty else { return }

        let userRef = db.collection(usersCollection).document(normalizedUserDocumentID)
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
        userDocumentID: String,
        onUpdate: @escaping (String?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        let normalizedUserDocumentID = normalizeUserID(userDocumentID)
        guard !normalizedUserDocumentID.isEmpty else {
            onUpdate(nil)
            return EmptyListenerRegistration()
        }

        let sessionRef = db.collection(usersCollection)
            .document(normalizedUserDocumentID)
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
