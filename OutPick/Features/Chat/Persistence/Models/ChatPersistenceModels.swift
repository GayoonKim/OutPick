import Foundation

struct LocalChatUser: Codable, Hashable {
    let userID: String
    var nickname: String
    var profileImagePath: String?
}

struct ImageIndexMeta: Decodable, Equatable {
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

struct VideoIndexMeta: Decodable, Equatable {
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
