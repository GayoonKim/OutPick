//
//  FirestoreCommentUserStateRepository.swift
//  OutPick
//
//  Created by Codex on 5/14/26.
//

import Foundation
import FirebaseFirestore

final class FirestoreCommentUserStateRepository: CommentUserStateRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchCommentUserStates(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentIDs: [CommentID]
    ) async throws -> [CommentID: CommentUserState] {
        var states: [CommentID: CommentUserState] = [:]
        let uniqueCommentIDs = Array(Set(commentIDs))

        for commentID in uniqueCommentIDs {
            let doc = try await db
                .collection("users")
                .document(userID.value)
                .collection("commentStates")
                .document(Self.commentStateDocumentID(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID,
                    commentID: commentID
                ))
                .getDocument()

            guard doc.exists else { continue }
            let dto: CommentUserStateDTO = try FirestoreMapper.mapDocument(doc)
            states[commentID] = dto.toDomain(commentID: commentID, userID: userID)
        }

        return states
    }

    private static func commentStateDocumentID(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID
    ) -> String {
        "\(brandID.value)_\(seasonID.value)_\(postID.value)_\(commentID.value)"
    }
}
