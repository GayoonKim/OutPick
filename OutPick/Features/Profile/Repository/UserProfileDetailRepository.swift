//
//  UserProfileDetailRepository.swift
//  OutPick
//

import Foundation

final class UserProfileDetailRepository: UserProfileDetailRepositoryProtocol {
    private let publicProfileRepository: UserPublicProfileRepositoryProtocol

    init(publicProfileRepository: UserPublicProfileRepositoryProtocol) {
        self.publicProfileRepository = publicProfileRepository
    }

    func fetchUserProfile(userID: String) async throws -> UserPublicProfile {
        try await publicProfileRepository.fetchProfile(userID: userID)
    }
}
