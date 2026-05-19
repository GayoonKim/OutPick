//
//  CloudFunctionsCommentEngagementRepository.swift
//  OutPick
//
//  Created by Codex on 5/14/26.
//

import Foundation

final class CloudFunctionsCommentEngagementRepository: CommentEngagementRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        isLiked: Bool
    ) async throws -> CommentEngagementResult {
        try await cloudFunctionsManager.setCommentEngagement(
            brandID: brandID.value,
            seasonID: seasonID.value,
            postID: postID.value,
            commentID: commentID.value,
            isLiked: isLiked
        )
    }
}
