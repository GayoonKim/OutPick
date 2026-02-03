//
//  CommentDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct CommentDTO: Codable {
    @DocumentID var id: String?

    /// comments가 `posts/{postId}/comments/{commentId}`라면 postID는 경로에서 주입 추천
    let postID: String?

    let userID: String
    let message: String
    let createdAt: Timestamp?
    let isDeleted: Bool?

    func toDomain(postID: PostID) throws -> Comment {
        guard let id else { throw MappingError.missingDocumentID }

        return Comment(
            id: CommentID(value: id),
            postID: postID,
            userID: UserID(value: userID),
            message: message,
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            isDeleted: isDeleted ?? false
        )
    }

    /// 선택: 문서에 postID가 포함된 경우
    func toDomainFromEmbeddedPostID() throws -> Comment {
        guard let embeddedPostID = postID, !embeddedPostID.isEmpty else {
            throw MappingError.missingRequiredField("postID")
        }
        return try toDomain(postID: PostID(value: embeddedPostID))
    }
}
