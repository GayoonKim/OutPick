//
//  CloudFunctionsUserBlockRepository.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation
import FirebaseFirestore

final class CloudFunctionsUserBlockRepository: UserBlockRepositoryProtocol, UserBlockRelationReading {
    private let transport: any CloudFunctionsTransporting
    private let db: Firestore

    init(
        transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport(),
        db: Firestore = Firestore.firestore()
    ) {
        self.transport = transport
        self.db = db
    }

    func blockUser(
        blockerUserID: UserID,
        blockedUserID: UserID,
        blockedUserNicknameSnapshot: String?,
        source: UserBlockSource
    ) async throws -> UserBlock {
        var data: [String: Any] = [
            "targetUID": blockedUserID.value,
            "source": source.rawValue,
            "clientRequestID": UUID().uuidString
        ]
        if let blockedUserNicknameSnapshot {
            data["targetNicknameSnapshot"] = blockedUserNicknameSnapshot
        }
        let response = try await transport.call("blockUser", data: data)
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard try decoder.bool("blocked") else {
            throw CloudFunctionsClientError.invalidResponse
        }
        return UserBlock(
            blockerUserID: blockerUserID,
            blockedUserID: blockedUserID,
            blockedUserNicknameSnapshot: blockedUserNicknameSnapshot,
            source: source,
            createdAt: decoder.optionalDate("updatedAt") ?? Date()
        )
    }

    func unblockUser(
        blockerUserID: UserID,
        blockedUserID: UserID
    ) async throws {
        let response = try await transport.call("unblockUser", data: [
            "targetUID": blockedUserID.value,
            "clientRequestID": UUID().uuidString
        ])
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard try decoder.bool("blocked") == false else {
            throw CloudFunctionsClientError.invalidResponse
        }
    }

    func fetchBlockedUsers(
        blockerUserID: UserID
    ) async throws -> [UserBlock] {
        let snapshot = try await db
            .collection("users")
            .document(blockerUserID.value)
            .collection("blockedUsers")
            .getDocuments()

        return snapshot.documents.compactMap { document in
            let data = document.data()
            let source = (data["source"] as? String)
                .flatMap(UserBlockSource.init(rawValue:)) ?? .profile
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                ?? (data["updatedAt"] as? Timestamp)?.dateValue()
                ?? .distantPast
            return UserBlock(
                blockerUserID: blockerUserID,
                blockedUserID: UserID(value: document.documentID),
                blockedUserNicknameSnapshot: data["blockedUserNicknameSnapshot"] as? String,
                source: source,
                createdAt: createdAt
            )
        }.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.blockedUserID.value < rhs.blockedUserID.value
        }
    }

    func fetchBlockedUserIDs(
        blockerUserID: UserID
    ) async throws -> Set<UserID> {
        Set(try await fetchBlockedUsers(blockerUserID: blockerUserID).map(\.blockedUserID))
    }

    func fetchHiddenCommentUserIDs(
        currentUserID: UserID
    ) async throws -> Set<UserID> {
        try await fetchBlockedUserIDs(blockerUserID: currentUserID)
    }
}
