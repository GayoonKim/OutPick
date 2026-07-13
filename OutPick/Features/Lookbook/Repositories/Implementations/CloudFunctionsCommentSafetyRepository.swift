//
//  CloudFunctionsCommentSafetyRepository.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation

final class CloudFunctionsCommentSafetyRepository: CommentSafetyRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func reportComment(
        reporterUserID: UserID,
        target: CommentReportTarget,
        reason: CommentReportReason,
        detail: String?
    ) async throws -> CommentReport {
        var data: [String: Any] = [
            "reporterUserID": reporterUserID.value,
            "targetType": target.targetType.rawValue,
            "brandID": target.brandID.value,
            "seasonID": target.seasonID.value,
            "postID": target.postID.value,
            "commentID": target.commentID.value,
            "reason": reason.rawValue
        ]
        if let value = target.parentCommentID?.value { data["parentCommentID"] = value }
        if let value = target.authorNicknameSnapshot {
            data["targetAuthorNicknameSnapshot"] = value
        }
        if let detail { data["detail"] = detail }
        let response = try await transport.call("reportComment", data: data)
        return try CommentCloudFunctionsMapper.report(response)
    }
}
