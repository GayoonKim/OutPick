//
//  ChatRoomParticipantsRepository.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

protocol ChatRoomParticipantsRepositoryProtocol {
    func fetchLocalChatUser(userID: String) throws -> LocalChatUser?
    @discardableResult
    func upsertLocalChatUser(userID: String, nickname: String, profileImagePath: String?) throws -> LocalChatUser
}
