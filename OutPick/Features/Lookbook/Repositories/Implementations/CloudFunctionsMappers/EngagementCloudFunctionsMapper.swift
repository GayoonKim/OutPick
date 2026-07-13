import Foundation

enum EngagementCloudFunctionsMapper {
    static func brand(_ dictionary: [String: Any]) throws -> BrandEngagementResult {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return BrandEngagementResult(
            brandID: BrandID(value: try decoder.string("brandID")),
            userID: UserID(value: try decoder.string("userID")),
            isLiked: try decoder.bool("isLiked"),
            likeCount: try decoder.int("likeCount")
        )
    }

    static func post(
        _ dictionary: [String: Any],
        brandID: BrandID,
        seasonID: SeasonID
    ) throws -> PostEngagementResult {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        let metrics = CloudFunctionResponseDecoder(
            dictionary: try decoder.nestedDictionary("metrics")
        )
        return PostEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: PostID(value: try decoder.string("postID")),
            userID: UserID(value: try decoder.string("userID")),
            isLiked: try decoder.bool("isLiked"),
            isSaved: try decoder.bool("isSaved"),
            metrics: PostMetrics(
                likeCount: try metrics.int("likeCount"),
                commentCount: try metrics.int("commentCount"),
                replacementCount: try metrics.int("replacementCount"),
                saveCount: try metrics.int("saveCount"),
                viewCount: metrics.optionalInt("viewCount")
            )
        )
    }

    static func season(_ dictionary: [String: Any]) throws -> SeasonEngagementResult {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return SeasonEngagementResult(
            brandID: BrandID(value: try decoder.string("brandID")),
            seasonID: SeasonID(value: try decoder.string("seasonID")),
            userID: UserID(value: try decoder.string("userID")),
            isLiked: try decoder.bool("isLiked"),
            likeCount: try decoder.int("likeCount")
        )
    }

    static func comment(_ dictionary: [String: Any]) throws -> CommentEngagementResult {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return CommentEngagementResult(
            brandID: BrandID(value: try decoder.string("brandID")),
            seasonID: SeasonID(value: try decoder.string("seasonID")),
            postID: PostID(value: try decoder.string("postID")),
            commentID: CommentID(value: try decoder.string("commentID")),
            userID: UserID(value: try decoder.string("userID")),
            parentCommentID: decoder.optionalString("parentCommentID").map(CommentID.init(value:)),
            isLiked: try decoder.bool("isLiked"),
            likeCount: try decoder.int("likeCount")
        )
    }
}
