//
//  CommentSafetyRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation

protocol CommentSafetyRepositoryProtocol {
    func reportComment(
        reporterUserID: UserID,
        target: CommentReportTarget,
        reason: CommentReportReason,
        detail: String?
    ) async throws -> CommentReport
}
