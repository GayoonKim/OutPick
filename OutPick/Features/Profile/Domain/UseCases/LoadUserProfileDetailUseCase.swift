//
//  LoadUserProfileDetailUseCase.swift
//  OutPick
//

import Foundation

protocol LoadUserProfileDetailUseCaseProtocol {
    func execute(email: String) async throws -> UserProfile
    func execute(userID: String) async throws -> UserProfile
}

final class LoadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol {
    private let repository: UserProfileDetailRepositoryProtocol

    init(repository: UserProfileDetailRepositoryProtocol) {
        self.repository = repository
    }

    func execute(email: String) async throws -> UserProfile {
        try await repository.fetchUserProfile(email: email)
    }

    func execute(userID: String) async throws -> UserProfile {
        try await repository.fetchUserProfile(userID: userID)
    }
}
