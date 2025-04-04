import Foundation

struct ChatMessage: Codable {
    let roomName: String
    let senderID: String
    let senderNickname: String
    let msg: String
    let sentAt: Date
    let attachments: [MediaItem]?
    
    var isFromCurrentUser: Bool {
        return senderID == LoginManager.shared.getUserEmail
    }
}

struct MediaItem: Codable {
    let type: MediaType
    let url: String
    let thumbnailUrl: String?
    
    enum MediaType: String, Codable {
        case image
        case video
    }
} 