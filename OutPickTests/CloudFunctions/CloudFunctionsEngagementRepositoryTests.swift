import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsEngagementRepositoryTests {
    @Test func coversEngagementCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            ["brandID": "brand-1", "userID": "user-1", "isLiked": true, "likeCount": 1],
            ["brandID": "brand-1", "seasonID": "season-1", "userID": "user-1", "isLiked": true, "likeCount": 2],
            Self.postResponse(isLiked: true, isSaved: false),
            Self.postResponse(isLiked: true, isSaved: true),
            [
                "brandID": "brand-1", "seasonID": "season-1", "postID": "post-1",
                "commentID": "comment-1", "userID": "user-1", "isLiked": true, "likeCount": 3
            ]
        ]
        let brand = CloudFunctionsBrandEngagementRepository(transport: transport)
        let season = CloudFunctionsSeasonEngagementRepository(transport: transport)
        let post = CloudFunctionsPostEngagementRepository(transport: transport)
        let comment = CloudFunctionsCommentEngagementRepository(transport: transport)
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let postID = PostID(value: "post-1")

        _ = try await brand.setLike(brandID: brandID, isLiked: true)
        _ = try await season.setLike(brandID: brandID, seasonID: seasonID, isLiked: true)
        _ = try await post.setLike(brandID: brandID, seasonID: seasonID, postID: postID, isLiked: true)
        let saved = try await post.setSave(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            isSaved: true
        )
        _ = try await comment.setLike(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: CommentID(value: "comment-1"),
            isLiked: true
        )

        #expect(transport.calls.map(\.name) == [
            "setBrandEngagement", "setSeasonEngagement", "setPostEngagement",
            "setPostEngagement", "setCommentEngagement"
        ])
        #expect(transport.calls[2].data["kind"] as? String == "like")
        #expect(transport.calls[2].data["isEnabled"] as? Bool == true)
        #expect(transport.calls[3].data["kind"] as? String == "save")
        #expect(saved.isSaved)
    }

    private static func postResponse(isLiked: Bool, isSaved: Bool) -> [String: Any] {
        [
            "postID": "post-1", "userID": "user-1", "isLiked": isLiked, "isSaved": isSaved,
            "metrics": ["likeCount": 1, "commentCount": 2, "replacementCount": 0, "saveCount": 1]
        ]
    }
}
