//
//  CloudFunctionsUserBlockRepository.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation
import FirebaseFirestore

final class CloudFunctionsUserBlockRepository: UserBlockRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager
    private let db: Firestore

    init(
        cloudFunctionsManager: CloudFunctionsManager = .shared,
        db: Firestore = Firestore.firestore()
    ) {
        self.cloudFunctionsManager = cloudFunctionsManager
        self.db = db
    }

    func blockUser(
        blockerUserID: UserID,
        blockedUserID: UserID,
        blockedUserNicknameSnapshot: String?,
        source: UserBlockSource
    ) async throws -> UserBlock {
        try await cloudFunctionsManager.blockUser(
            blockerUserID: blockerUserID.value,
            blockedUserID: blockedUserID.value,
            blockedUserNicknameSnapshot: blockedUserNicknameSnapshot,
            source: source
        )
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
        try await cloudFunctionsManager.loadHiddenCommentUserIDs(
            currentUserID: currentUserID.value
        )
    }
}
