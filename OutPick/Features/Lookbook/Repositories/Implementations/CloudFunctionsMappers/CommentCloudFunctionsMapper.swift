import Foundation

enum CommentCloudFunctionsMapper {
    static func mutation(_ dictionary: [String: Any]) throws -> CommentMutationResult {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return CommentMutationResult(
            brandID: BrandID(value: try decoder.string("brandID")),
            seasonID: SeasonID(value: try decoder.string("seasonID")),
            postID: PostID(value: try decoder.string("postID")),
            commentID: CommentID(value: try decoder.string("commentID")),
            userID: UserID(value: try decoder.string("userID")),
            parentCommentID: decoder.optionalString("parentCommentID").map(CommentID.init(value:)),
            commentCount: try decoder.int("commentCount"),
            replyCount: try decoder.int("replyCount")
        )
    }

    static func deletion(_ dictionary: [String: Any]) throws -> CommentDeletionResult {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return CommentDeletionResult(
            brandID: BrandID(value: try decoder.string("brandID")),
            seasonID: SeasonID(value: try decoder.string("seasonID")),
            postID: PostID(value: try decoder.string("postID")),
            commentID: CommentID(value: try decoder.string("commentID")),
            userID: UserID(value: try decoder.string("userID")),
            parentCommentID: decoder.optionalString("parentCommentID").map(CommentID.init(value:)),
            targetType: CommentSafetyTargetType(
                rawValue: try decoder.string("targetType")
            ) ?? .comment,
            deletedReplyCount: try decoder.int("deletedReplyCount"),
            deletedCommentCount: try decoder.int("deletedCommentCount"),
            commentCount: try decoder.int("commentCount"),
            replyCount: try decoder.int("replyCount")
        )
    }

    static func report(_ dictionary: [String: Any]) throws -> CommentReport {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        let target = CommentReportTarget(
            targetType: CommentSafetyTargetType(
                rawValue: try decoder.string("targetType")
            ) ?? .comment,
            brandID: BrandID(value: try decoder.string("brandID")),
            seasonID: SeasonID(value: try decoder.string("seasonID")),
            postID: PostID(value: try decoder.string("postID")),
            commentID: CommentID(value: try decoder.string("targetCommentID")),
            parentCommentID: decoder.optionalString("parentCommentID").map(CommentID.init(value:)),
            authorID: UserID(value: try decoder.string("targetAuthorID")),
            contentSnapshot: try decoder.string("targetContentSnapshot"),
            authorNicknameSnapshot: decoder.optionalString("targetAuthorNicknameSnapshot")
        )
        return CommentReport(
            id: CommentReportID(value: try decoder.string("reportID")),
            reporterUserID: UserID(value: try decoder.string("reporterUserID")),
            target: target,
            reason: CommentReportReason(rawValue: try decoder.string("reason")) ?? .other,
            detail: decoder.optionalString("detail"),
            status: CommentReportStatus(rawValue: try decoder.string("status")) ?? .pending,
            createdAt: try decoder.date("createdAtMillis")
        )
    }

    static func userBlock(_ dictionary: [String: Any]) throws -> UserBlock {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return UserBlock(
            blockerUserID: UserID(value: try decoder.string("blockerUserID")),
            blockedUserID: UserID(value: try decoder.string("blockedUserID")),
            blockedUserNicknameSnapshot: decoder.optionalString("blockedUserNicknameSnapshot"),
            source: UserBlockSource(rawValue: try decoder.string("source")) ?? .profile,
            createdAt: try decoder.date("createdAtMillis")
        )
    }
}
