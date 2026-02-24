//
//  ChatRoomSearchUseCase.swift
//  OutPick
//
//  Created by Codex on 2/11/26.
//

import Foundation

protocol ChatRoomSearchUseCaseProtocol {
    func searchMessages(roomID: String, keyword: String) async throws -> [ChatMessage]
    func applyHighlight(messageIDs: Set<String>) -> Set<String>
    func clearHighlight() -> Set<String>
}

final class ChatRoomSearchUseCase: ChatRoomSearchUseCaseProtocol {
    private let searchManager: ChatSearchManaging

    init(searchManager: ChatSearchManaging) {
        self.searchManager = searchManager
    }

    func searchMessages(roomID: String, keyword: String) async throws -> [ChatMessage] {
        try await searchManager.searchMessages(roomID: roomID, keyword: keyword)
    }

    func applyHighlight(messageIDs: Set<String>) -> Set<String> {
        searchManager.applyHighlight(messageIDs: messageIDs)
    }

    func clearHighlight() -> Set<String> {
        searchManager.clearHighlight()
    }
}
