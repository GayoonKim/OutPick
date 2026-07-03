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

    func fetchUserProfile(userID: String) async throws -> UserProfile {
        try await userProfileRepository.fetchUserProfile(userID: userID)
    }
}
