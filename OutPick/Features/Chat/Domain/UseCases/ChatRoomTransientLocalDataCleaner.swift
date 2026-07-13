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
    private let localDataStore: ChatRoomLocalDataPersisting

    init(localDataStore: ChatRoomLocalDataPersisting) {
        self.localDataStore = localDataStore
    }

    func cleanTransientLocalRoomData(roomID: String) async throws {
        try localDataStore.cleanTransientRoomData(roomID: roomID)
    }
}
