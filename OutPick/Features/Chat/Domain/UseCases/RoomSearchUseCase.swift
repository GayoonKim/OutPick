//
//  RoomSearchUseCase.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

struct RoomSearchPage {
    let rooms: [ChatRoom]
    let hasMore: Bool
}

protocol RoomSearchUseCaseProtocol {
    func searchRooms(keyword: String, limit: Int, reset: Bool) async throws -> RoomSearchPage
    func loadMoreSearchRooms(limit: Int) async throws -> RoomSearchPage
}

final class RoomSearchUseCase: RoomSearchUseCaseProtocol {
    private let roomRepository: FirebaseChatRoomRepositoryProtocol

    init(roomRepository: FirebaseChatRoomRepositoryProtocol) {
        self.roomRepository = roomRepository
    }

    func searchRooms(keyword: String, limit: Int = 30, reset: Bool = true) async throws -> RoomSearchPage {
        try await roomRepository.searchRooms(keyword: keyword, limit: limit, reset: reset)
    }

    func loadMoreSearchRooms(limit: Int = 30) async throws -> RoomSearchPage {
        try await roomRepository.loadMoreSearchRooms(limit: limit)
    }
}
