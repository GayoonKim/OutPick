//
//  PostUserStateDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct PostUserStateDTO: Decodable {
    /// 보통 `users/{userId}/postStates/{postId}` 구조라서 userID/postID는 경로로 주입하는 편이 깔끔합니다.
    let brandID: String?
    let seasonID: String?
    let postID: String?
    let userID: String?

    let isLiked: Bool?
    let isSaved: Bool?
    let updatedAt: Timestamp?
    let likedAt: Timestamp?

    func toDomain(
        brandID: BrandID? = nil,
        seasonID: SeasonID? = nil,
        postID: PostID,
        userID: UserID
    ) -> PostUserState {
        PostUserState(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: userID,
            isLiked: isLiked ?? false,
            isSaved: isSaved ?? false,
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            likedAt: likedAt?.dateValue()
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
            brandID: brandID.map { BrandID(value: $0) },
            seasonID: seasonID.map { SeasonID(value: $0) },
            postID: PostID(value: embeddedPostID),
            userID: UserID(value: embeddedUserID)
        )
    }

    func toLikedDomain(userID: UserID) throws -> PostUserState {
        guard let embeddedBrandID = brandID, !embeddedBrandID.isEmpty else {
            throw MappingError.missingRequiredField("brandID")
        }
        guard let embeddedSeasonID = seasonID, !embeddedSeasonID.isEmpty else {
            throw MappingError.missingRequiredField("seasonID")
        }
        guard let embeddedPostID = postID, !embeddedPostID.isEmpty else {
            throw MappingError.missingRequiredField("postID")
        }
        return toDomain(
            brandID: BrandID(value: embeddedBrandID),
            seasonID: SeasonID(value: embeddedSeasonID),
            postID: PostID(value: embeddedPostID),
            userID: userID
        )
    }
}
