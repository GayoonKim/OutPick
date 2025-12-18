//
//  PostUserStateDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct PostUserStateDTO: Codable {
    @DocumentID var id: String?

    /// 보통 `users/{userId}/postStates/{postId}` 구조라서 userID/postID는 경로로 주입하는 편이 깔끔합니다.
    let postID: String?
    let userID: String?

    let isLiked: Bool?
    let isSaved: Bool?
    let updatedAt: Timestamp?

    func toDomain(postID: PostID, userID: UserID) -> PostUserState {
        PostUserState(
            postID: postID,
            userID: userID,
            isLiked: isLiked ?? false,
            isSaved: isSaved ?? false,
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }

    /// 선택: 문서 필드로 userID/postID가 들어있는 경우
    func toDomainFromEmbeddedIDs() throws -> PostUserState {
        guard let embeddedPostID = postID, !embeddedPostID.isEmpty else {
            throw MappingError.missingRequiredField("postID")
        }
        guard let embeddedUserID = userID, !embeddedUserID.isEmpty else {
            throw MappingError.missingRequiredField("userID")
        }
        return toDomain(
            postID: PostID(value: embeddedPostID),
            userID: UserID(value: embeddedUserID)
        )
    }
}
