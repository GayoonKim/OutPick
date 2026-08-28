import Foundation
import Testing
@testable import OutPick

@MainActor
struct ChatMessageReportViewModelTests {
    @Test
    func networkFailureKeepsRequestIdentityAndInputForRetry() async {
        let useCase = MessageReportUseCaseFake(results: [
            .failure(TestError.network),
            .success(Self.receipt(status: .accepted))
        ])
        let requestID = UUID(uuidString: "123E4567-E89B-42D3-A456-426614174000")!
        let viewModel = ChatMessageReportViewModel(
            roomID: "room-1",
            messageID: "message-1",
            isMediaContext: false,
            useCase: useCase,
            clientRequestID: requestID
        )
        viewModel.selectedReason = .harassment
        viewModel.detail = "반복적인 괴롭힘"

        #expect(await viewModel.submit() == nil)
        #expect(viewModel.clientRequestID == requestID)
        #expect(await viewModel.submit() == .accepted)
        #expect(useCase.commands.count == 2)
        #expect(useCase.commands[0].clientRequestID == useCase.commands[1].clientRequestID)
        #expect(useCase.commands[1].detail == "반복적인 괴롭힘")
    }

    @Test
    func terminalFailureRotatesIdentityButKeepsFormInput() async {
        let useCase = MessageReportUseCaseFake(results: [
            .success(Self.receipt(status: .failed))
        ])
        let requestID = UUID(uuidString: "123E4567-E89B-42D3-A456-426614174000")!
        let viewModel = ChatMessageReportViewModel(
            roomID: "room-1",
            messageID: "message-1",
            isMediaContext: true,
            useCase: useCase,
            clientRequestID: requestID
        )
        viewModel.selectedReason = .privacy
        viewModel.detail = "개인정보가 보여요"

        #expect(await viewModel.submit() == nil)
        #expect(viewModel.clientRequestID != requestID)
        #expect(viewModel.selectedReason == .privacy)
        #expect(viewModel.detail == "개인정보가 보여요")
    }

    @Test
    func mapsProcessingDuplicateAndDeletedCompletions() async {
        let useCase = MessageReportUseCaseFake(results: [
            .success(Self.receipt(status: .processing)),
            .success(Self.receipt(status: .alreadyReported)),
            .success(Self.receipt(status: .messageAlreadyDeleted, seq: 7))
        ])
        let viewModel = ChatMessageReportViewModel(
            roomID: "room-1",
            messageID: "message-1",
            isMediaContext: false,
            useCase: useCase
        )
        viewModel.selectedReason = .spam

        #expect(await viewModel.submit() == .processing)
        #expect(await viewModel.submit() == .alreadyReported)
        #expect(await viewModel.submit() == .messageAlreadyDeleted(seq: 7))
    }

    private static func receipt(
        status: ChatMessageReportStatus,
        seq: Int64? = 1
    ) -> ChatMessageReportReceipt {
        ChatMessageReportReceipt(
            status: status,
            submissionID: status == .messageAlreadyDeleted ? nil : "submission-1",
            isDeduplicated: false,
            isAlreadyReported: status == .alreadyReported,
            visibilityState: status == .messageAlreadyDeleted ? "deleted" : "visible",
            seq: seq,
            receivedAt: status == .accepted ? Date() : nil,
            originalReceivedAt: nil
        )
    }
}

private enum TestError: Error {
    case network
}

@MainActor
private final class MessageReportUseCaseFake: SubmitChatModerationReportUseCaseProtocol {
    private var results: [Result<ChatMessageReportReceipt, Error>]
    private(set) var commands: [ChatMessageReportCommand] = []

    init(results: [Result<ChatMessageReportReceipt, Error>]) {
        self.results = results
    }

    func submitMessageReport(
        _ command: ChatMessageReportCommand
    ) async throws -> ChatMessageReportReceipt {
        commands.append(command)
        return try results.removeFirst().get()
    }

    func submitUserReport(
        _ command: ChatUserReportCommand
    ) async throws -> ChatModerationReportReceipt {
        fatalError("사용하지 않는 테스트 경로")
    }

    func submitRoomReport(
        _ command: ChatRoomReportCommand
    ) async throws -> ChatModerationReportReceipt {
        fatalError("사용하지 않는 테스트 경로")
    }
}
