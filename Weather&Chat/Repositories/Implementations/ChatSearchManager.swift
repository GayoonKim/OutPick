//
//  ChatSearchManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

final class ChatSearchManager: ChatSearchManagerProtocol {
    private let grdbManager: GRDBManager
    
    init(grdbManager: GRDBManager = .shared) {
        self.grdbManager = grdbManager
    }
    
    func searchMessages(roomID: String, keyword: String) async throws -> [ChatMessage] {
        return try await grdbManager.fetchMessages(in: roomID, containing: keyword)
    }
    
    func applyHighlight(messageIDs: Set<String>) -> Set<String> {
        return messageIDs
    }
    
    func clearHighlight() -> Set<String> {
        return []
    }
}

