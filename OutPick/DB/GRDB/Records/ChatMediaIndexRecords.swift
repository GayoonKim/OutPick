import Foundation
import GRDB

struct ImageIndexRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "imageIndex"

    let roomID: String
    let messageID: String
    let idx: Int
    let thumbKey: String?
    let originalKey: String?
    let thumbURL: String?
    let originalURL: String?
    let width: Int?
    let height: Int?
    let bytesOriginal: Int?
    let hash: String?
    let isFailed: Bool
    let localThumb: String?
    let sentAt: Date
}

struct VideoIndexRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "videoIndex"

    let roomID: String
    let messageID: String
    let idx: Int
    let thumbKey: String?
    let originalKey: String?
    let thumbURL: String?
    let originalURL: String?
    let width: Int?
    let height: Int?
    let bytesOriginal: Int?
    let duration: Double?
    let approxBitrateMbps: Double?
    let preset: String?
    let hash: String?
    let isFailed: Bool
    let localThumb: String?
    let sentAt: Date
}
