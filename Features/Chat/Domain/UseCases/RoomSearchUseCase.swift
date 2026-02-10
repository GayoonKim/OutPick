//
//  RoomSearchUseCase.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

protocol RoomSearchUseCaseProtocol {
    func searchRooms(keyword: String, limit: Int, reset: Bool) async throws -> [ChatRoom]
    func loadMoreSearchRooms(limit: Int) async throws -> [ChatRoom]
}

final class RoomSearchUseCase: RoomSearchUseCaseProtocol {
    private let roomRepository: ChatRoomRepositoryProtocol

    init(roomRepository: ChatRoomRepositoryProtocol) {
        self.roomRepository = roomRepository
    }

    func searchRooms(keyword: String, limit: Int = 30, reset: Bool = true) async throws -> [ChatRoom] {
        try await roomRepository.searchRooms(keyword: keyword, limit: limit, reset: reset)
    }

    func loadMoreSearchRooms(limit: Int = 30) async throws -> [ChatRoom] {
        try await roomRepository.loadMoreSearchRooms(limit: limit)
    }
}
