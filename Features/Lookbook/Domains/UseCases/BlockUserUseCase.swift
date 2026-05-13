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
    private let debugFailureInjectionStore: LookbookDebugFailureInjectionStore?

    init(
        repository: any UserBlockRepositoryProtocol,
        debugFailureInjectionStore: LookbookDebugFailureInjectionStore? = nil
    ) {
        self.repository = repository
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
        return try await repository.blockUser(
            blockerUserID: blockerUserID,
            blockedUserID: blockedUserID,
            blockedUserNicknameSnapshot: nicknameSnapshot,
            source: source
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
