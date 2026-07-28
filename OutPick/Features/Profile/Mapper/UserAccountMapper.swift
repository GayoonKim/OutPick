import Foundation

enum UserAccountMapper {
    static func toDomain(_ dto: UserAccountDTO) throws -> UserAccount {
        guard let status = UserAccountStatus(rawValue: dto.accountStatus) else {
            throw FirebaseError.FailedToFetchProfile
        }
        return UserAccount(
            userID: dto.userID,
            onboardingVersion: dto.onboardingVersion,
            selectedMoodIDs: dto.selectedMoodIDs,
            accountStatus: status,
            onboardingCompletedAt: dto.onboardingCompletedAt,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}
