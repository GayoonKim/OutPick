import Foundation

enum ChatMediaUploadReservationError: Error, Equatable, Sendable {
    case activeUploadLimit
}

enum ChatMediaServerProcessingStatus: String, Codable, Equatable, Sendable {
    case uploading
    case queued
    case processing
    case ready
    case canceled
    case failed
    case expired
}

struct ChatMediaSourceDescriptor: Codable, Equatable, Sendable {
    let index: Int
    let fileURL: URL
    let contentType: String
    let sizeBytes: Int64
    let sha256: String
    let mediaFormat: String
    let isAnimated: Bool

    init(
        index: Int,
        fileURL: URL,
        contentType: String,
        sizeBytes: Int64,
        sha256: String,
        mediaFormat: String,
        isAnimated: Bool
    ) {
        self.index = index
        self.fileURL = fileURL
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.mediaFormat = mediaFormat
        self.isAnimated = isAnimated
    }
}

struct ChatMediaUploadTarget: Codable, Equatable, Sendable {
    let attachmentID: String
    let sourceIndex: Int
    let path: String
    let signedURL: URL
    let requiredHeaders: [String: String]
    let contentType: String
    let sizeBytes: Int64
    let sha256: String
}

struct ChatMediaUploadReservation: Codable, Equatable, Sendable {
    let uploadID: String
    let clientMutationID: String
    let processingStatus: ChatMediaServerProcessingStatus
    let targets: [ChatMediaUploadTarget]
    let expiresAt: Date
}

struct ChatMediaUploadedSource: Codable, Equatable, Sendable {
    let attachmentID: String
    let sourceIndex: Int
    let path: String
    let sizeBytes: Int64
}

struct ChatMediaProcessingSnapshot: Codable, Equatable, Sendable {
    let uploadID: String
    let processingStatus: ChatMediaServerProcessingStatus
    let messageID: String?
    let seq: Int64?
    let retryable: Bool
    let failureCode: String?
}

enum ChatMediaRestoreReconciliationResult: Equatable, Sendable {
    case resume(ChatMediaProcessingSnapshot)
    case manualRetry
}
