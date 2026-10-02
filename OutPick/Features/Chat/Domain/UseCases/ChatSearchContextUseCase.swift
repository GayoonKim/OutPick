import Foundation

final class ChatSearchContextUseCase {
    private let repository: FirebaseMessageRepositoryProtocol
    private let persistence: any ChatMessagePersisting
    private let messages: any ChatRoomMessageUseCaseProtocol
    init(repository: FirebaseMessageRepositoryProtocol, persistence: any ChatMessagePersisting, messages: any ChatRoomMessageUseCaseProtocol) {
        self.repository = repository; self.persistence = persistence; self.messages = messages
    }
    func load(room: ChatRoom, target: ChatSearchResultMetadata, source: ChatMessageSearchSource) async throws -> [ChatMessage] {
        do { return try await loadWindow(room: room, target: target, source: source) }
        catch { throw ChatSearchValidationRepository.classify(error) }
    }
    private func loadWindow(room: ChatRoom, target: ChatSearchResultMetadata, source: ChatMessageSearchSource) async throws -> [ChatMessage] {
        let anchor: ChatMessage?
        if source == .serverIndex {
            guard let range = ChatMessageSequenceRange(lower: target.seq, upper: target.seq) else { throw ChatSearchFailure.malformedData }
            anchor = try await repository.fetchMessageRange(roomID: room.id, range: range).first { $0.ID == target.messageID }
        } else { anchor = try await persistence.fetchMessage(id: target.messageID, inRoom: room.id) }
        guard let anchor, anchor.seq == target.seq, !anchor.isDeleted else { throw ChatSearchFailure.malformedData }
        let window: [ChatMessage]
        if source == .serverIndex {
            window = try await messages.loadMessagesAroundAnchor(room: room, anchor: anchor, beforeLimit: 60, afterLimit: 60)
        } else {
            async let older = persistence.fetchMessagesBeforeSeq(inRoom: room.id, beforeSeq: anchor.seq, limit: 60)
            async let newer = persistence.fetchMessagesAfterSeq(inRoom: room.id, afterSeq: anchor.seq, limit: 60)
            let pair = try await (older, newer)
            window = pair.0 + [anchor] + pair.1
        }
        return try await messages.sanitizeForAdmission(window, roomID: room.id)
    }
}
