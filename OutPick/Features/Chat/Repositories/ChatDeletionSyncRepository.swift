import Foundation

protocol ChatDeletionSyncRepositoryProtocol {
    func headRevision(roomID: String) async throws -> Int64
    func deltas(roomID: String, afterRevision: Int64, limit: Int) async throws -> [ChatDeletionDelta]
    func deltas(roomID: String, messageIDs: [String]) async throws -> [ChatDeletionDelta]
}
final class FirebaseChatDeletionSyncRepository: ChatDeletionSyncRepositoryProtocol {
    private let messageRepository: FirebaseMessageRepositoryProtocol

    init(messageRepository: FirebaseMessageRepositoryProtocol) {
        self.messageRepository = messageRepository
    }

    func headRevision(roomID: String) async throws -> Int64 {
        try await messageRepository.fetchMessageDeletionRevision(roomID: roomID)
    }

    func deltas(roomID: String, afterRevision: Int64, limit: Int) async throws -> [ChatDeletionDelta] {
        try await messageRepository.fetchDeletionDeltas(
            roomID: roomID,
            afterRevision: afterRevision,
            limit: limit
        )
    }

    func deltas(roomID: String, messageIDs: [String]) async throws -> [ChatDeletionDelta] {
        try await messageRepository.fetchDeletionDeltas(roomID: roomID, messageIDs: messageIDs)
    }
}
