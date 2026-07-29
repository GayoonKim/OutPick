import Foundation

enum AccountDeletionStatus: String, Codable, Equatable, Sendable {
    case grace
    case finalizing
    case retryPending
    case completed
    case cancelled

    var isCancelable: Bool {
        self == .grace
    }
}

struct AccountDeletionIntent: Equatable, Sendable {
    let intentID: String
    let nonce: String
    let expiresAt: Date
}

struct AccountDeletionReceipt: Codable, Equatable, Sendable {
    let requestID: String
    let receiptToken: String
    let requestedAt: Date
    let cancelableUntil: Date
    let provider: AuthProvider
}

struct AccountDeletionStatusSnapshot: Equatable, Sendable {
    let status: AccountDeletionStatus
    let requestedAt: Date?
    let cancelableUntil: Date?
    let completedAt: Date?
    let message: String
}

struct AccountDeletionCancellation: Equatable, Sendable {
    let requestID: String
    let cancelledAt: Date
}

enum AccountDeletionClientError: Error, Equatable {
    case invalidResponse
    case identityMismatch
    case providerMismatch
    case missingAuthenticatedUser
    case receiptPersistenceFailed
}

enum AccountDeletionISO8601 {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter = ISO8601DateFormatter()

    static func date(from string: String) -> Date? {
        fractionalFormatter.date(from: string) ?? standardFormatter.date(from: string)
    }
}
