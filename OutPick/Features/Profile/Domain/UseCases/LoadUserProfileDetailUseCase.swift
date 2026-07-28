//
//  LoadUserProfileDetailUseCase.swift
//  OutPick
//

import Foundation

protocol LoadUserProfileDetailUseCaseProtocol {
    func execute(userID: String) async throws -> UserPublicProfile
}

final class LoadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol {
    private let repository: UserProfileDetailRepositoryProtocol

    init(repository: UserProfileDetailRepositoryProtocol) {
        self.repository = repository
    }

    func execute(userID: String) async throws -> UserPublicProfile {
        try await repository.fetchUserProfile(userID: userID)
    }
}
