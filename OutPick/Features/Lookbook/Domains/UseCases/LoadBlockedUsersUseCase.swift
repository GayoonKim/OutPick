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

protocol LoadHiddenCommentUserIDsUseCaseProtocol {
    func execute(
        currentUserID: UserID
    ) async throws -> Set<UserID>
}

final class LoadHiddenCommentUserIDsUseCase: LoadHiddenCommentUserIDsUseCaseProtocol {
    private let repository: any UserBlockRepositoryProtocol
    private let visibilityStore: (any UserBlockVisibilityChecking)?

    init(
        repository: any UserBlockRepositoryProtocol,
        visibilityStore: (any UserBlockVisibilityChecking)? = nil
    ) {
        self.repository = repository
        self.visibilityStore = visibilityStore
    }

    func execute(
        currentUserID: UserID
    ) async throws -> Set<UserID> {
        if let visibilityStore {
            return Set(visibilityStore.blockedUserIDs().map(UserID.init(value:)))
        }
        return try await repository.fetchHiddenCommentUserIDs(currentUserID: currentUserID)
    }
}
