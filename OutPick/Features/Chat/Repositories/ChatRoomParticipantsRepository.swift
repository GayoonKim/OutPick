//
//  ChatRoomParticipantsRepository.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

protocol ChatRoomParticipantsRepositoryProtocol {
    func fetchLocalChatUser(userID: String) throws -> LocalChatUser?
    func upsertLocalChatUser(userID: String, nickname: String, profileImagePath: String?) throws
}

final class GRDBChatRoomParticipantsRepository: ChatRoomParticipantsRepositoryProtocol {
    private let grdbManager: GRDBManager

    init(grdbManager: GRDBManager = .shared) {
        self.grdbManager = grdbManager
    }

    func fetchLocalChatUser(userID: String) throws -> LocalChatUser? {
        try grdbManager.fetchLocalChatUser(userID: userID)
    }

    func upsertLocalChatUser(userID: String, nickname: String, profileImagePath: String?) throws {
        _ = try grdbManager.upsertLocalChatUser(
            userID: userID,
            nickname: nickname,
            profileImagePath: profileImagePath
        )
    }
}
