import Foundation
import GRDB

struct ChatMessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chatMessage"

    let id: String
    let seq: Int64
    let roomID: String
    let senderUID: String
    let senderEmail: String?
    let senderNickname: String
    let senderAvatarPath: String?
    let messageType: String?
    let msg: String?
    let sentAt: Date?
    let attachments: String
    let sharedContent: String?
    let isFailed: Bool
    let replyPreview: String?
    let isDeleted: Bool
}
