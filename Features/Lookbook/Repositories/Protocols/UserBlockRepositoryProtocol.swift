//
//  UserBlockRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation

protocol UserBlockRepositoryProtocol {
    func blockUser(
        blockerUserID: UserID,
        blockedUserID: UserID,
        blockedUserNicknameSnapshot: String?,
        source: UserBlockSource
    ) async throws -> UserBlock

    func fetchBlockedUserIDs(
        blockerUserID: UserID
    ) async throws -> Set<UserID>
}
