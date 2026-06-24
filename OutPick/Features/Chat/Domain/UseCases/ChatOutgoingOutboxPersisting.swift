//
//  ChatOutgoingOutboxPersisting.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import Foundation

protocol ChatOutgoingOutboxPersisting {
    func saveChatMessages(_ messages: [ChatMessage]) async throws
    func fetchMessage(id messageID: String, inRoom roomID: String) async throws -> ChatMessage?
    func hardDeleteMessage(id messageID: String, inRoom roomID: String) async throws
    func saveOutgoingOutboxRecord(_ record: ChatOutgoingOutboxRecord) async throws
    func fetchOutgoingOutboxRecord(messageID: String) async throws -> ChatOutgoingOutboxRecord?
    func deleteOutgoingOutboxRecord(messageID: String) async throws
}
