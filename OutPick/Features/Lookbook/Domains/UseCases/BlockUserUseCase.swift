//
//  BlockUserUseCase.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation

protocol BlockUserUseCaseProtocol {
    func execute(
        blockerUserID: UserID,
        blockedUserID: UserID,
        blockedUserNicknameSnapshot: String?,
        source: UserBlockSource
    ) async throws -> UserBlock
}

final class BlockUserUseCase: BlockUserUseCaseProtocol {
    private let repository: any UserBlockRepositoryProtocol
    private weak var sessionSynchronizer: (any UserBlockSessionSynchronizing)?
    private let debugFailureInjectionStore: LookbookDebugFailureInjectionStore?

    init(
        repository: any UserBlockRepositoryProtocol,
        sessionSynchronizer: (any UserBlockSessionSynchronizing)? = nil,
        debugFailureInjectionStore: LookbookDebugFailureInjectionStore? = nil
    ) {
        self.repository = repository
        self.sessionSynchronizer = sessionSynchronizer
        self.debugFailureInjectionStore = debugFailureInjectionStore
    }

    func execute(
        blockerUserID: UserID,
        blockedUserID: UserID,
        blockedUserNicknameSnapshot: String?,
        source: UserBlockSource
    ) async throws -> UserBlock {
        guard blockerUserID != blockedUserID else {
            throw CommentSafetyError.cannotBlockSelf
        }

        let nicknameSnapshot = blockedUserNicknameSnapshot?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        try debugFailureInjectionStore?.throwIfNeeded(.blockUser)
        let result = try await repository.blockUser(
            blockerUserID: blockerUserID,
            blockedUserID: blockedUserID,
            blockedUserNicknameSnapshot: nicknameSnapshot,
            source: source
        )
        await sessionSynchronizer?.applyServerMutation(
            userID: blockerUserID.value,
            targetUserID: blockedUserID.value,
            isBlocked: true
        )
        return result
    }
}

protocol UnblockUserUseCaseProtocol {
    func execute(blockerUserID: UserID, blockedUserID: UserID) async throws
}

final class UnblockUserUseCase: UnblockUserUseCaseProtocol {
    private let repository: any UserBlockRepositoryProtocol
    private weak var sessionSynchronizer: (any UserBlockSessionSynchronizing)?

    init(
        repository: any UserBlockRepositoryProtocol,
        sessionSynchronizer: (any UserBlockSessionSynchronizing)? = nil
    ) {
        self.repository = repository
        self.sessionSynchronizer = sessionSynchronizer
    }

    func execute(blockerUserID: UserID, blockedUserID: UserID) async throws {
        guard blockerUserID != blockedUserID else {
            throw CommentSafetyError.cannotBlockSelf
        }
        try await repository.unblockUser(
            blockerUserID: blockerUserID,
            blockedUserID: blockedUserID
        )
        await sessionSynchronizer?.applyServerMutation(
            userID: blockerUserID.value,
            targetUserID: blockedUserID.value,
            isBlocked: false
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
