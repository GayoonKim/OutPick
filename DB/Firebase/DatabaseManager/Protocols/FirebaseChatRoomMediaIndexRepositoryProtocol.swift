//
//  FirebaseChatRoomMediaIndexRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation
import FirebaseFirestore

protocol FirebaseChatRoomMediaIndexRepositoryProtocol {
    func addMediaIndexWrites(for message: ChatMessage, in batch: WriteBatch)
    func markMediaIndexDeleted(roomID: String, messageID: String) async throws
    func fetchLatestMedia(inRoom roomID: String, limit: Int) async throws -> [ChatRoomMediaIndexEntry]
    func fetchOlderMedia(
        inRoom roomID: String,
        before cursor: ChatRoomMediaIndexCursor,
        limit: Int
    ) async throws -> [ChatRoomMediaIndexEntry]
}
