import Foundation

protocol ChatProfileCachePersisting: ChatRoomParticipantsRepositoryProtocol {
    func upsertRoomProfileDisplayCache(
        roomID: String,
        userID: String,
        lastSeenAt: Date,
        lastMessageSeq: Int?,
        lastMessageID: String?,
        updatedAt: Date,
        maxEntriesPerRoom: Int
    ) throws
    func fetchRoomProfileDisplayCacheUserIDs(roomID: String) throws -> [String]
    func countRoomProfileDisplayCache(roomID: String) throws -> Int
}

extension ChatProfileCachePersisting {
    func upsertRoomProfileDisplayCache(
        roomID: String,
        userID: String,
        lastSeenAt: Date,
        lastMessageSeq: Int?,
        lastMessageID: String?,
        maxEntriesPerRoom: Int = 20
    ) throws {
        try upsertRoomProfileDisplayCache(
            roomID: roomID,
            userID: userID,
            lastSeenAt: lastSeenAt,
            lastMessageSeq: lastMessageSeq,
            lastMessageID: lastMessageID,
            updatedAt: Date(),
            maxEntriesPerRoom: maxEntriesPerRoom
        )
    }
}
