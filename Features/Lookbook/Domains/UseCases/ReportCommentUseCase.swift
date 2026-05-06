//
//  ReportCommentUseCase.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation

enum CommentSafetyError: Error {
    case cannotReportOwnContent
    case emptyReportTarget
    case cannotBlockSelf
}

protocol ReportCommentUseCaseProtocol {
    func execute(
        reporterUserID: UserID,
        target: CommentReportTarget,
        reason: CommentReportReason,
        detail: String?
    ) async throws -> CommentReport
}

final class ReportCommentUseCase: ReportCommentUseCaseProtocol {
    private let repository: any CommentSafetyRepositoryProtocol
    private let maxDetailLength: Int

    init(
        repository: any CommentSafetyRepositoryProtocol,
        maxDetailLength: Int = 500
    ) {
        self.repository = repository
        self.maxDetailLength = maxDetailLength
    }

    func execute(
        reporterUserID: UserID,
        target: CommentReportTarget,
        reason: CommentReportReason,
        detail: String?
    ) async throws -> CommentReport {
        guard reporterUserID != target.authorID else {
            throw CommentSafetyError.cannotReportOwnContent
        }

        let normalizedContent = target.contentSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedContent.isEmpty == false else {
            throw CommentSafetyError.emptyReportTarget
        }

        let normalizedDetail = detail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxDetailLength)
        let reportDetail = normalizedDetail.flatMap {
            $0.isEmpty ? nil : String($0)
        }
        var normalizedTarget = target
        normalizedTarget.contentSnapshot = normalizedContent

        return try await repository.reportComment(
            reporterUserID: reporterUserID,
            target: normalizedTarget,
            reason: reason,
            detail: reportDetail
        )
    }
}
