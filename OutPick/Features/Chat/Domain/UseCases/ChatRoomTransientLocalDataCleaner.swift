//
//  ChatRoomTransientLocalDataCleaner.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

protocol ChatRoomTransientLocalDataCleaning {
    func cleanTransientLocalRoomData(roomID: String) async throws
}

final class DefaultChatRoomTransientLocalDataCleaner: ChatRoomTransientLocalDataCleaning {
    private let grdbManager: GRDBManager

    init(grdbManager: GRDBManager = .shared) {
        self.grdbManager = grdbManager
    }

    func cleanTransientLocalRoomData(roomID: String) async throws {
        try grdbManager.deleteMessages(inRoom: roomID)
        try grdbManager.deleteImages(inRoom: roomID)
    }
}
