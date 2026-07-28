import Foundation

struct UserPublicProfile: Equatable {
    var userID: String
    var nickname: String
    var avatarThumbPath: String?
    var avatarOriginalPath: String?
    var createdAt: Date?
    var updatedAt: Date?
}
