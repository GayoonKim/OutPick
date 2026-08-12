protocol ChatOutgoingOutboxPersisting {
    func saveOutgoingOutboxRecord(_ record: ChatOutgoingOutboxRecord) async throws
    func fetchOutgoingOutboxRecord(messageID: String) async throws -> ChatOutgoingOutboxRecord?
    func fetchOutgoingOutboxRecords(messageIDs: [String]) async throws -> [ChatOutgoingOutboxRecord]
    func fetchOutgoingOutboxRecords(roomID: String) async throws -> [ChatOutgoingOutboxRecord]
    func deleteOutgoingOutboxRecord(messageID: String) async throws
    func deleteOutgoingOutboxRecords(messageIDs: [String]) async throws
    func deleteOutgoingOutboxRecords(roomID: String) async throws
}
