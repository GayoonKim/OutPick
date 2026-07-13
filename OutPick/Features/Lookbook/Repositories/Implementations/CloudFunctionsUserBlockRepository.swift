//
//  CloudFunctionsUserBlockRepository.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation
import FirebaseFirestore

final class CloudFunctionsUserBlockRepository: UserBlockRepositoryProtocol {
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
            "blockerUserID": blockerUserID.value,
            "blockedUserID": blockedUserID.value,
            "source": source.rawValue
        ]
        if let blockedUserNicknameSnapshot {
            data["blockedUserNicknameSnapshot"] = blockedUserNicknameSnapshot
        }
        let response = try await transport.call("blockUser", data: data)
        return try CommentCloudFunctionsMapper.userBlock(response)
    }

    func fetchBlockedUserIDs(
        blockerUserID: UserID
    ) async throws -> Set<UserID> {
        let snapshot = try await db
            .collection("users")
            .document(blockerUserID.value)
            .collection("blockedUsers")
            .getDocuments()

        return Set(snapshot.documents.map { UserID(value: $0.documentID) })
    }

    func fetchHiddenCommentUserIDs(
        currentUserID: UserID
    ) async throws -> Set<UserID> {
        let response = try await transport.call(
            "loadHiddenCommentUserIDs",
            data: ["currentUserID": currentUserID.value]
        )
        return Set(
            CloudFunctionResponseDecoder(dictionary: response)
                .stringArray("hiddenUserIDs")
                .map(UserID.init(value:))
        )
    }
}
