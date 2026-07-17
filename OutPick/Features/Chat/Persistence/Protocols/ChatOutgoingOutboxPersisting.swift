protocol ChatOutgoingOutboxPersisting {
    func saveOutgoingOutboxRecord(_ record: ChatOutgoingOutboxRecord) async throws
    func fetchOutgoingOutboxRecord(messageID: String) async throws -> ChatOutgoingOutboxRecord?
    func fetchOutgoingOutboxRecords(messageIDs: [String]) async throws -> [ChatOutgoingOutboxRecord]
    func deleteOutgoingOutboxRecord(messageID: String) async throws
    func deleteOutgoingOutboxRecords(messageIDs: [String]) async throws
}
