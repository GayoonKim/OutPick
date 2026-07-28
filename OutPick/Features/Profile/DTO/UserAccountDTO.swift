import FirebaseFirestore
import Foundation

struct UserAccountDTO {
    let userID: String
    let onboardingVersion: Int
    let selectedMoodIDs: [String]
    let accountStatus: String
    let onboardingCompletedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    init?(userID: String, data: [String: Any]) {
        guard let accountStatus = data["accountStatus"] as? String else {
            return nil
        }
        self.userID = userID
        self.onboardingVersion = Self.int(data["onboardingVersion"]) ?? 0
        self.selectedMoodIDs = data["selectedMoodIDs"] as? [String] ?? []
        self.accountStatus = accountStatus
        self.onboardingCompletedAt = Self.date(data["onboardingCompletedAt"])
        self.createdAt = Self.date(data["createdAt"])
        self.updatedAt = Self.date(data["updatedAt"])
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}
