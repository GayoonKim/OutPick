//
//  CloudFunctionsCommentWritingRepository.swift
//  OutPick
//
//  Created by Codex on 5/4/26.
//

import Foundation

final class CloudFunctionsCommentWritingRepository: CommentWritingRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func createComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        message: String
    ) async throws -> CommentMutationResult {
        let response = try await transport.call(
            "createComment",
            data: [
                "brandID": brandID.value,
                "seasonID": seasonID.value,
                "postID": postID.value,
                "message": message
            ]
        )
        return try CommentCloudFunctionsMapper.mutation(response)
    }

    func createReply(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        message: String
    ) async throws -> CommentMutationResult {
        let response = try await transport.call(
            "createReply",
            data: [
                "brandID": brandID.value,
                "seasonID": seasonID.value,
                "postID": postID.value,
                "parentCommentID": parentCommentID.value,
                "message": message
            ]
        )
        return try CommentCloudFunctionsMapper.mutation(response)
    }

    func deleteComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        reason: String?
    ) async throws -> CommentDeletionResult {
        var data: [String: Any] = [
            "brandID": brandID.value,
            "seasonID": seasonID.value,
            "postID": postID.value,
            "commentID": commentID.value
        ]
        if let reason { data["reason"] = reason }
        let response = try await transport.call("deleteComment", data: data)
        return try CommentCloudFunctionsMapper.deletion(response)
    }
}
