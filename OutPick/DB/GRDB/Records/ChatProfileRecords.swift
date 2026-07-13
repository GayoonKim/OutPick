import Foundation
import GRDB

struct LocalChatUserRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "LocalChatUser"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let userID: String
    let nickname: String
    let profileImagePath: String?
}

struct RoomProfileDisplayCacheRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "RoomProfileDisplayCache"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let roomID: String
    let userID: String
    let lastSeenAt: Date
    let lastMessageSeq: Int?
    let lastMessageID: String?
    let updatedAt: Date
}
