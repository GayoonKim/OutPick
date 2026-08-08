import Foundation

enum AccountModerationStatus: String, Equatable {
    case active
    case restricted
    case suspended
}

enum ModerationCapability: String, Equatable {
    case readAppContent
    case createUGC
    case updateUGC
    case deleteOwnUGC
    case createRoom
    case joinRoom
    case moderateOwnedRoom
    case report
    case block
    case unblock
    case support
    case deleteAccount
}

struct CurrentUserModerationState: Equatable {
    let status: AccountModerationStatus
    let restrictedUntil: Date?
    let allowedCapabilities: Set<ModerationCapability>
    let noticeReasonCode: String?
    let supportURL: URL?

    func allows(_ capability: ModerationCapability) -> Bool {
        allowedCapabilities.contains(capability)
    }
}
