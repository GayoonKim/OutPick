//
//  CloudFunctionsCommentSafetyRepository.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation

final class CloudFunctionsCommentSafetyRepository: CommentSafetyRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func reportComment(
        reporterUserID: UserID,
        target: CommentReportTarget,
        reason: CommentReportReason,
        detail: String?
    ) async throws -> CommentReport {
        try await cloudFunctionsManager.reportComment(
            reporterUserID: reporterUserID.value,
            target: target,
            reason: reason,
            detail: detail
        )
    }
}
