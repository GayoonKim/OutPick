//
//  ChatRoomParticipantsRepository.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

protocol ChatRoomParticipantsRepositoryProtocol {
    func fetchLocalUsersPage(roomID: String, offset: Int, limit: Int) throws -> ([LocalUser], Int)
    func fetchLocalUser(email: String) throws -> LocalUser?
    func userEmails(in roomID: String) throws -> [String]
    func upsertLocalUser(email: String, nickname: String, profileImagePath: String?) throws
    func addLocalUser(_ email: String, toRoom roomID: String) throws
    func removeLocalUser(_ email: String, fromRoom roomID: String) throws
}

final class GRDBChatRoomParticipantsRepository: ChatRoomParticipantsRepositoryProtocol {
    private let grdbManager: GRDBManager

    init(grdbManager: GRDBManager = .shared) {
        self.grdbManager = grdbManager
    }

    func fetchLocalUsersPage(roomID: String, offset: Int, limit: Int) throws -> ([LocalUser], Int) {
        try grdbManager.fetchLocalUsersPage(roomID: roomID, offset: offset, limit: limit)
    }

    func fetchLocalUser(email: String) throws -> LocalUser? {
        try grdbManager.fetchLocalUser(email: email)
    }

    func userEmails(in roomID: String) throws -> [String] {
        try grdbManager.userEmails(in: roomID)
    }

    func upsertLocalUser(email: String, nickname: String, profileImagePath: String?) throws {
        _ = try grdbManager.upsertLocalUser(
            email: email,
            nickname: nickname,
            profileImagePath: profileImagePath
        )
    }

    func addLocalUser(_ email: String, toRoom roomID: String) throws {
        try grdbManager.addLocalUser(email, toRoom: roomID)
    }

    func removeLocalUser(_ email: String, fromRoom roomID: String) throws {
        try grdbManager.removeLocalUser(email, fromRoom: roomID)
    }
}
