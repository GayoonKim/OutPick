import FirebaseFirestore
import Foundation

struct UserPublicProfileDTO {
    let userID: String
    let nickname: String
    let avatarThumbPath: String?
    let avatarOriginalPath: String?
    let createdAt: Date?
    let updatedAt: Date?

    init?(userID: String, data: [String: Any]) {
        guard let nickname = data["nickname"] as? String,
              nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        self.userID = userID
        self.nickname = nickname
        self.avatarThumbPath = Self.optionalString(data["avatarThumbPath"])
        self.avatarOriginalPath = Self.optionalString(data["avatarOriginalPath"])
        self.createdAt = Self.date(data["createdAt"])
        self.updatedAt = Self.date(data["updatedAt"])
    }

    private static func optionalString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}
