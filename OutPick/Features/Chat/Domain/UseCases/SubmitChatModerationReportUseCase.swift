import Foundation

protocol SubmitChatModerationReportUseCaseProtocol {
    func submitUserReport(
        _ command: ChatUserReportCommand
    ) async throws -> ChatModerationReportReceipt

    func submitRoomReport(
        _ command: ChatRoomReportCommand
    ) async throws -> ChatModerationReportReceipt
}

enum SubmitChatModerationReportError: LocalizedError, Equatable {
    case missingTarget
    case missingRoomContext
    case detailTooLong

    var errorDescription: String? {
        switch self {
        case .missingTarget:
            return "신고 대상을 확인할 수 없습니다."
        case .missingRoomContext:
            return "신고할 채팅방을 확인할 수 없습니다."
        case .detailTooLong:
            return "신고 상세 내용은 500자까지 입력할 수 있습니다."
        }
    }
}

final class SubmitChatModerationReportUseCase:
    SubmitChatModerationReportUseCaseProtocol {
    private let repository: any ChatModerationReportingRepositoryProtocol

    init(repository: any ChatModerationReportingRepositoryProtocol) {
        self.repository = repository
    }

    func submitUserReport(
        _ command: ChatUserReportCommand
    ) async throws -> ChatModerationReportReceipt {
        guard !command.targetUserID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw SubmitChatModerationReportError.missingTarget
        }
        if command.triggerMessageID != nil && command.roomID == nil {
            throw SubmitChatModerationReportError.missingRoomContext
        }
        try validateDetail(command.detail)
        return try await repository.submitUserReport(command)
    }

    func submitRoomReport(
        _ command: ChatRoomReportCommand
    ) async throws -> ChatModerationReportReceipt {
        guard !command.roomID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw SubmitChatModerationReportError.missingRoomContext
        }
        try validateDetail(command.detail)
        return try await repository.submitRoomReport(command)
    }

    private func validateDetail(_ detail: String?) throws {
        if let detail, detail.count > 500 {
            throw SubmitChatModerationReportError.detailTooLong
        }
    }
}
