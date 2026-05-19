//
//  RemoteChatRoomMediaIndexRepository.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

protocol RemoteChatRoomMediaIndexRepositoryProtocol {
    func fetchLatestMedia(inRoom roomID: String, limit: Int) async throws -> [ChatRoomMediaIndexEntry]
    func fetchOlderMedia(
        inRoom roomID: String,
        before cursor: ChatRoomMediaIndexCursor,
        limit: Int
    ) async throws -> [ChatRoomMediaIndexEntry]
}

final class FirebaseChatRoomMediaIndexAdapter: RemoteChatRoomMediaIndexRepositoryProtocol {
    private let repository: FirebaseChatRoomMediaIndexRepositoryProtocol

    init(repository: FirebaseChatRoomMediaIndexRepositoryProtocol) {
        self.repository = repository
    }

    func fetchLatestMedia(inRoom roomID: String, limit: Int) async throws -> [ChatRoomMediaIndexEntry] {
        try await repository.fetchLatestMedia(inRoom: roomID, limit: limit)
    }

    func fetchOlderMedia(
        inRoom roomID: String,
        before cursor: ChatRoomMediaIndexCursor,
        limit: Int
    ) async throws -> [ChatRoomMediaIndexEntry] {
        try await repository.fetchOlderMedia(inRoom: roomID, before: cursor, limit: limit)
    }
}
