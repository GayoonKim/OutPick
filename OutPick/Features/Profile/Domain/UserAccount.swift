import Foundation

enum UserAccountStatus: String, Equatable {
    case active
    case deletionPending
}

struct UserAccount: Equatable {
    let userID: String
    let onboardingVersion: Int
    let selectedMoodIDs: [String]
    let accountStatus: UserAccountStatus
    let onboardingCompletedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
}
