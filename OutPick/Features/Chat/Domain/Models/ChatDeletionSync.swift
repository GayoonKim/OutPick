import Foundation

struct ChatDeletionDelta: Equatable, Sendable {
    let messageID: String
    let roomID: String
    let seq: Int64
    let revision: Int64
    let deletedAt: Date?
    let anonymizesSender: Bool

    init(
        messageID: String,
        roomID: String,
        seq: Int64,
        revision: Int64,
        deletedAt: Date?,
        anonymizesSender: Bool = false
    ) {
        self.messageID = messageID
        self.roomID = roomID
        self.seq = seq
        self.revision = revision
        self.deletedAt = deletedAt
        self.anonymizesSender = anonymizesSender
    }
}

struct ChatDeletionCleanupItem: Equatable, Sendable {
    enum Kind: String, Sendable {
        case image
        case video
        case localFile
    }

    let kind: Kind
    let path: String
}

struct ChatDeletionSocketEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case message(ChatDeletionDelta)
        case headAdvanced(fromRevision: Int64, toRevision: Int64)
    }

    let roomID: String
    let kind: Kind
}

enum ChatDeletionSyncError: LocalizedError, Equatable {
    case invalidHead
    case revisionGap(expected: Int64, actual: Int64?)

    var errorDescription: String? {
        switch self {
        case .invalidHead:
            return "삭제 동기화 상태를 확인할 수 없습니다. 다시 시도해 주세요."
        case .revisionGap:
            return "삭제된 메시지를 모두 동기화하지 못했습니다. 다시 시도해 주세요."
        }
    }
}
