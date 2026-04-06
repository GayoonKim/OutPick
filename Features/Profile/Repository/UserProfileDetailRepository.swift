//
//  UserProfileDetailRepository.swift
//  OutPick
//

import Foundation

final class UserProfileDetailRepository: UserProfileDetailRepositoryProtocol {
    private let userProfileRepository: UserProfileRepositoryProtocol

    init(userProfileRepository: UserProfileRepositoryProtocol) {
        self.userProfileRepository = userProfileRepository
    }

    func fetchUserProfile(email: String) async throws -> UserProfile {
        try await userProfileRepository.fetchUserProfileFromFirestore(email: email)
    }
}
