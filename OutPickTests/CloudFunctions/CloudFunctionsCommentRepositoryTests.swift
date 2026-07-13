import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsCommentRepositoryTests {
    @Test func coversCommentMutationSafetyAndBlockCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            Self.mutation(commentID: "comment-1", parentCommentID: nil),
            Self.mutation(commentID: "reply-1", parentCommentID: "comment-1"),
            [
                "brandID": "brand-1", "seasonID": "season-1", "postID": "post-1",
                "commentID": "comment-1", "userID": "user-1", "targetType": "comment",
                "deletedReplyCount": 1, "deletedCommentCount": 2, "commentCount": 0, "replyCount": 0
            ],
            [
                "reportID": "report-1", "reporterUserID": "user-1", "targetType": "comment",
                "brandID": "brand-1", "seasonID": "season-1", "postID": "post-1",
                "targetCommentID": "comment-1", "targetAuthorID": "user-2",
                "targetContentSnapshot": "content", "reason": "spam", "status": "pending",
                "createdAtMillis": 1_700_000_000_000 as NSNumber
            ],
            [
                "blockerUserID": "user-1", "blockedUserID": "user-2", "source": "comment",
                "createdAtMillis": 1_700_000_000_000 as NSNumber
            ],
            ["hiddenUserIDs": ["user-2", "user-3"]]
        ]
        let writing = CloudFunctionsCommentWritingRepository(transport: transport)
        let safety = CloudFunctionsCommentSafetyRepository(transport: transport)
        let blocking = CloudFunctionsUserBlockRepository(transport: transport)
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let postID = PostID(value: "post-1")
        let commentID = CommentID(value: "comment-1")

        _ = try await writing.createComment(
            brandID: brandID, seasonID: seasonID, postID: postID, message: "comment"
        )
        _ = try await writing.createReply(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            parentCommentID: commentID,
            message: "reply"
        )
        _ = try await writing.deleteComment(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: commentID,
            reason: nil
        )
        let target = CommentReportTarget(
            targetType: .comment,
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: commentID,
            parentCommentID: nil,
            authorID: UserID(value: "user-2"),
            contentSnapshot: "content",
            authorNicknameSnapshot: nil
        )
        _ = try await safety.reportComment(
            reporterUserID: UserID(value: "user-1"),
            target: target,
            reason: .spam,
            detail: nil
        )
        _ = try await blocking.blockUser(
            blockerUserID: UserID(value: "user-1"),
            blockedUserID: UserID(value: "user-2"),
            blockedUserNicknameSnapshot: nil,
            source: .comment
        )
        let hidden = try await blocking.fetchHiddenCommentUserIDs(
            currentUserID: UserID(value: "user-1")
        )

        #expect(transport.calls.map(\.name) == [
            "createComment", "createReply", "deleteComment", "reportComment",
            "blockUser", "loadHiddenCommentUserIDs"
        ])
        #expect(transport.calls[2].data["reason"] == nil)
        #expect(transport.calls[3].data["targetAuthorID"] == nil)
        #expect(hidden == Set([UserID(value: "user-2"), UserID(value: "user-3")]))
    }

    private static func mutation(
        commentID: String,
        parentCommentID: String?
    ) -> [String: Any] {
        var value: [String: Any] = [
            "brandID": "brand-1", "seasonID": "season-1", "postID": "post-1",
            "commentID": commentID, "userID": "user-1", "commentCount": 1, "replyCount": 0
        ]
        if let parentCommentID { value["parentCommentID"] = parentCommentID }
        return value
    }
}
