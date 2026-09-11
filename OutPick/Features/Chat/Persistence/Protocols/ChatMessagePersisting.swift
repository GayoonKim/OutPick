import Foundation

protocol ChatMessagePersisting: ChatFailedOutgoingMessagePersisting {
    func saveAuthoritativeIdentityRepair(_ messages: [ChatMessage], accountID: String, session: ChatMessageCacheSession) async throws
    func saveChatMessages(_ messages: [ChatMessage], accountID: String, session: ChatMessageCacheSession) async throws
    func saveChatMessages(_ messages: [ChatMessage]) async throws
    func fetchRecentMessages(inRoom roomID: String, limit: Int) async throws -> [ChatMessage]
    func fetchMessagesAfterSeq(inRoom roomID: String, afterSeq: Int64, limit: Int) async throws -> [ChatMessage]
    func fetchMessagesBeforeSeq(inRoom roomID: String, beforeSeq: Int64, limit: Int) async throws -> [ChatMessage]
    func fetchOlderMessages(inRoom roomID: String, before anchorMessageID: String, limit: Int) async throws -> [ChatMessage]
    func fetchNewerMessages(inRoom roomID: String, after anchorMessageID: String, limit: Int) async throws -> [ChatMessage]
    func fetchFailedOutgoingMessages(inRoom roomID: String, senderUID: String) async throws -> [ChatMessage]
    func applyDeletion(messageIDs: [String], inRoom roomID: String) async throws
}

extension ChatMessagePersisting {
    func saveAuthoritativeIdentityRepair(_ messages: [ChatMessage], accountID: String, session: ChatMessageCacheSession) async throws {
        try await saveChatMessages(messages, accountID: accountID, session: session)
    }
    func saveChatMessages(_ messages: [ChatMessage], accountID: String, session: ChatMessageCacheSession) async throws {
        guard messages.allSatisfy({ session.isValid(roomID: $0.roomID) }) else { throw CancellationError() }
        try await saveChatMessages(messages)
    }
}

protocol ChatMessageSearching {
    func fetchMessages(in roomID: String, containing keyword: String?) async throws -> [ChatMessage]
}

protocol ChatFailedOutgoingMessagePersisting {
    func saveChatMessages(_ messages: [ChatMessage]) async throws
    func fetchMessage(id messageID: String, inRoom roomID: String) async throws -> ChatMessage?
    func hardDeleteMessage(id messageID: String, inRoom roomID: String) async throws
    func deleteUnconfirmedMessage(id messageID: String, inRoom roomID: String) async throws
}

extension ChatFailedOutgoingMessagePersisting {
    func deleteUnconfirmedMessage(id messageID: String, inRoom roomID: String) async throws {
        guard try await fetchMessage(id: messageID, inRoom: roomID)?.seq ?? 0 <= 0 else { return }
        try await hardDeleteMessage(id: messageID, inRoom: roomID)
    }
}
