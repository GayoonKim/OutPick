import Foundation

@MainActor
final class ChatMessageReportViewModel {
    enum State: Equatable {
        case idle
        case submitting
        case error(String)
    }

    enum Completion: Equatable {
        case accepted
        case processing
        case alreadyReported
        case messageAlreadyDeleted(seq: Int64?)
    }

    let isMediaContext: Bool
    private let roomID: String
    private let messageID: String
    private let useCase: any SubmitChatModerationReportUseCaseProtocol
    private(set) var clientRequestID: UUID
    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    var selectedReason: ChatModerationReportReason?
    var detail = ""
    var onStateChange: ((State) -> Void)?

    init(
        roomID: String,
        messageID: String,
        isMediaContext: Bool,
        useCase: any SubmitChatModerationReportUseCaseProtocol,
        clientRequestID: UUID = UUID()
    ) {
        self.roomID = roomID
        self.messageID = messageID
        self.isMediaContext = isMediaContext
        self.useCase = useCase
        self.clientRequestID = clientRequestID
    }

    func submit() async -> Completion? {
        guard state != .submitting else { return nil }
        guard let selectedReason else {
            state = .error("신고 사유를 선택해 주세요.")
            return nil
        }

        state = .submitting
        do {
            let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let receipt = try await useCase.submitMessageReport(
                ChatMessageReportCommand(
                    roomID: roomID,
                    messageID: messageID,
                    reason: selectedReason,
                    detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
                    clientRequestID: clientRequestID
                )
            )
            switch receipt.status {
            case .accepted:
                state = .idle
                return .accepted
            case .processing:
                state = .idle
                return .processing
            case .alreadyReported:
                state = .idle
                return .alreadyReported
            case .messageAlreadyDeleted:
                state = .idle
                return .messageAlreadyDeleted(seq: receipt.seq)
            case .failed:
                clientRequestID = UUID()
                state = .error("신고를 완료하지 못했어요. 다시 시도해 주세요.")
                return nil
            }
        } catch {
            state = .error(Self.userMessage(for: error))
            return nil
        }
    }

    private static func userMessage(for error: Error) -> String {
        if error is CloudFunctionsTransportError {
            return "요청이 많아요. 잠시 후 다시 시도해 주세요."
        }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return "신고를 보내지 못했어요. 입력 내용은 그대로 유지됩니다."
    }
}
