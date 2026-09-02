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

    private func normalizeUserID(_ userID: String) -> String {
        userID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolveOrCreateUserDocumentID(authenticatedUser: AuthenticatedUser) async throws -> String {
        let normalizedIdentityKey = authenticatedUser.identityKey
        guard !normalizedIdentityKey.isEmpty, !authenticatedUser.providerUserID.isEmpty else {
            throw FirebaseError.FailedToFetchProfile
        }
        guard normalizedIdentityKey.contains("/") == false else {
            throw FirebaseError.FailedToFetchProfile
        }

        return normalizedIdentityKey
    }

    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws {
        try await updateReadFrontier(
            roomID: roomID,
            userUID: userUID,
            lastReadSeq: lastReadSeq,
            lastReadUnreadMessageSeq: lastReadSeq
        )
    }

    func updateReadFrontier(
        roomID: String,
        userUID: String,
        lastReadSeq: Int64,
        lastReadUnreadMessageSeq: Int64
    ) async throws {
        let trimmedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let userDocumentID = normalizeUserID(userUID)
        guard !trimmedRoomID.isEmpty, !userDocumentID.isEmpty else { return }

        let joinedRoomRef = db.collection("users").document(userDocumentID)
            .collection("joinedRooms").document(trimmedRoomID)

        do {
            let result = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let joinedRoomSnap = try transaction.getDocument(joinedRoomRef)

                    let requested = max(Int64(0), lastReadSeq)
                    let current = Self.toInt64(joinedRoomSnap.data()?["lastReadSeq"]) ?? 0
                    let currentUnread = Self.toInt64(
                        joinedRoomSnap.data()?["lastReadUnreadMessageSeq"]
                    ) ?? current
                    let next = max(current, requested)
                    let requestedUnread = max(Int64(0), lastReadUnreadMessageSeq)
                    let nextUnread = max(currentUnread, requestedUnread)
                    let didWrite = next > current || nextUnread > currentUnread

                    if didWrite {
                        transaction.setData([
                            "roomID": trimmedRoomID,
                            "lastReadSeq": next,
                            "lastReadUnreadMessageSeq": nextUnread,
                            "updatedAt": FieldValue.serverTimestamp()
                        ], forDocument: joinedRoomRef, merge: true)
                    }
                    return [
                        "current": current,
                        "requested": requested,
                        "next": next,
                        "didWrite": didWrite
                    ]
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            let values = result as? [String: Any]
            print(
                "[ChatReadPersistence][transaction] "
                    + "room=\(Self.maskedIdentifier(trimmedRoomID)) "
                    + "user=\(Self.maskedIdentifier(userDocumentID)) "
                    + "current=\(Self.toInt64(values?["current"]) ?? -1) "
                    + "requested=\(Self.toInt64(values?["requested"]) ?? lastReadSeq) "
                    + "next=\(Self.toInt64(values?["next"]) ?? -1) "
                    + "didWrite=\((values?["didWrite"] as? Bool) ?? false)"
            )
        } catch {
            print(
                "[ChatReadPersistence][transaction-failure] "
                    + "room=\(Self.maskedIdentifier(trimmedRoomID)) "
                    + "user=\(Self.maskedIdentifier(userDocumentID)) "
                    + "requested=\(lastReadSeq) error=\(error)"
            )
            throw error
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

    func fetchAuthoritativeLastReadSeq(for roomID: String, userUID: String) async throws -> Int64 {
        let trimmedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let userDocumentID = normalizeUserID(userUID)
        guard !trimmedRoomID.isEmpty, !userDocumentID.isEmpty else { return 0 }

        let docRef = db.collection("users").document(userDocumentID)
            .collection("joinedRooms").document(trimmedRoomID)
        let snapshot = try await docRef.getDocument(source: .server)
        return Self.toInt64(snapshot.data()?["lastReadSeq"]) ?? 0
    }

    private static func maskedIdentifier(_ value: String) -> String {
        guard value.count > 4 else { return "***" }
        return "\(value.prefix(2))…\(value.suffix(2))"
    }

    func upsertDeviceID(userDocumentID: String, email: String, deviceID: String) async throws {
        _ = email
        let normalizedUserDocumentID = normalizeUserID(userDocumentID)
        guard !normalizedUserDocumentID.isEmpty else { return }

        let userRef = db.collection(usersCollection).document(normalizedUserDocumentID)
        let sessionRef = userRef.collection("meta").document("session")
        try await sessionRef.setData([
            "deviceID": deviceID,
            "lastLoginAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
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
        guard !userDocumentID.isEmpty, !state.deviceID.isEmpty else { return }

        let deviceRef = db.collection(usersCollection).document(userDocumentID)
            .collection("devices").document(state.deviceID)

        var payload: [String: Any] = [
            "deviceID": state.deviceID,
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

        try await deviceRef.setData(payload, merge: true)
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
