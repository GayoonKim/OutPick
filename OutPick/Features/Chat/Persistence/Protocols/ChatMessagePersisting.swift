import Foundation

protocol ChatMessagePersisting: ChatFailedOutgoingMessagePersisting {
    func saveChatMessages(_ messages: [ChatMessage]) async throws
    func fetchRecentMessages(inRoom roomID: String, limit: Int) async throws -> [ChatMessage]
    func fetchMessagesAfterSeq(inRoom roomID: String, afterSeq: Int64, limit: Int) async throws -> [ChatMessage]
    func fetchMessagesBeforeSeq(inRoom roomID: String, beforeSeq: Int64, limit: Int) async throws -> [ChatMessage]
    func fetchOlderMessages(inRoom roomID: String, before anchorMessageID: String, limit: Int) async throws -> [ChatMessage]
    func fetchNewerMessages(inRoom roomID: String, after anchorMessageID: String, limit: Int) async throws -> [ChatMessage]
    func fetchFailedOutgoingMessages(inRoom roomID: String, senderUID: String) async throws -> [ChatMessage]
    func applyDeletion(messageIDs: [String], inRoom roomID: String) async throws
}

protocol ChatMessageSearching {
    func fetchMessages(in roomID: String, containing keyword: String?) async throws -> [ChatMessage]
}

protocol ChatFailedOutgoingMessagePersisting {
    func saveChatMessages(_ messages: [ChatMessage]) async throws
    func fetchMessage(id messageID: String, inRoom roomID: String) async throws -> ChatMessage?
    func hardDeleteMessage(id messageID: String, inRoom roomID: String) async throws
}
