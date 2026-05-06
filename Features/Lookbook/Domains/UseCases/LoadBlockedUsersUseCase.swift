//
//  LoadBlockedUsersUseCase.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation

protocol LoadBlockedUsersUseCaseProtocol {
    func execute(
        blockerUserID: UserID
    ) async throws -> Set<UserID>
}

final class LoadBlockedUsersUseCase: LoadBlockedUsersUseCaseProtocol {
    private let repository: any UserBlockRepositoryProtocol

    init(repository: any UserBlockRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        blockerUserID: UserID
    ) async throws -> Set<UserID> {
        try await repository.fetchBlockedUserIDs(blockerUserID: blockerUserID)
    }
}
