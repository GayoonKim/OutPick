//
//  PostUserState.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// 사용자별 상태(좋아요/저장)를 Post 모델에 섞지 않는" 편이 테스트/캐시가 편함
struct PostUserState: Equatable, Codable {
    var brandID: BrandID?
    var seasonID: SeasonID?
    var postID: PostID
    var userID: UserID
    var isLiked: Bool
    var isSaved: Bool
    var updatedAt: Date
    var likedAt: Date?

    init(
        brandID: BrandID? = nil,
        seasonID: SeasonID? = nil,
        postID: PostID,
        userID: UserID,
        isLiked: Bool,
        isSaved: Bool,
        updatedAt: Date,
        likedAt: Date? = nil
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.userID = userID
        self.isLiked = isLiked
        self.isSaved = isSaved
        self.updatedAt = updatedAt
        self.likedAt = likedAt
    }

    init(
        postID: PostID,
        userID: UserID,
        isLiked: Bool,
        isSaved: Bool,
        updatedAt: Date
    ) {
        self.init(
            brandID: nil,
            seasonID: nil,
            postID: postID,
            userID: userID,
            isLiked: isLiked,
            isSaved: isSaved,
            updatedAt: updatedAt,
            likedAt: nil
        )
    }
}
