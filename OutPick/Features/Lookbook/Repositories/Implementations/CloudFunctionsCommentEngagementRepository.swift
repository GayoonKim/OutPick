//
//  CloudFunctionsCommentEngagementRepository.swift
//  OutPick
//
//  Created by Codex on 5/14/26.
//

import Foundation

final class CloudFunctionsCommentEngagementRepository: CommentEngagementRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        isLiked: Bool
    ) async throws -> CommentEngagementResult {
        let response = try await transport.call(
            "setCommentEngagement",
            data: [
                "brandID": brandID.value,
                "seasonID": seasonID.value,
                "postID": postID.value,
                "commentID": commentID.value,
                "isLiked": isLiked
            ]
        )
        return try EngagementCloudFunctionsMapper.comment(response)
    }
}
