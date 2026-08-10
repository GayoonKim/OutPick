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
