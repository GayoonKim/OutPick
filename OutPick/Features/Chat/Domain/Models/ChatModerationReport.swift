import Foundation

enum ChatModerationReportReason: String, CaseIterable, Codable, Hashable {
    case harassment
    case hate
    case sexual
    case spam
    case privacy
    case illegalDangerous
    case other
}

struct ChatModerationReportReceipt: Equatable {
    let submissionID: String
    let isDeduplicated: Bool
    let receivedAt: Date
}

enum ChatMessageReportStatus: String, Equatable {
    case processing
    case accepted
    case alreadyReported
    case failed
    case messageAlreadyDeleted
}

struct ChatMessageReportReceipt: Equatable {
    let status: ChatMessageReportStatus
    let submissionID: String?
    let isDeduplicated: Bool
    let isAlreadyReported: Bool
    let visibilityState: String
    let seq: Int64?
    let receivedAt: Date?
    let originalReceivedAt: Date?
}

struct ChatMessageReportCommand: Equatable {
    let roomID: String
    let messageID: String
    let reason: ChatModerationReportReason
    let detail: String?
    let clientRequestID: UUID
}

struct ChatUserReportCommand: Equatable {
    let targetUserID: String
    let reason: ChatModerationReportReason
    let detail: String?
    let roomID: String?
    let triggerMessageID: String?
    let clientRequestID: UUID
}

struct ChatRoomReportCommand: Equatable {
    let roomID: String
    let reason: ChatModerationReportReason
    let detail: String?
    let triggerMessageID: String?
    let clientRequestID: UUID
}
