//
//  RoomListUseCase.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

struct ChatRoomPreviewItem: Hashable {
    let room: ChatRoom
    let messages: [ChatMessage]

    func hash(into hasher: inout Hasher) {
        hasher.combine(room.id)
    }

    static func == (lhs: ChatRoomPreviewItem, rhs: ChatRoomPreviewItem) -> Bool {
        lhs.room.id == rhs.room.id
    }
}

protocol RoomListUseCaseProtocol {
    @MainActor
    func cachedTopRooms() -> [ChatRoomPreviewItem]

    @MainActor
    func refreshTopRooms(limit: Int) async throws -> [ChatRoomPreviewItem]

    @MainActor
    func removeCachedRoom(roomID: String)
}

@MainActor
final class RoomListUseCase: RoomListUseCaseProtocol {
    private let roomRepository: FirebaseChatRoomRepositoryProtocol

    init(roomRepository: FirebaseChatRoomRepositoryProtocol) {
        self.roomRepository = roomRepository
    }

    func cachedTopRooms() -> [ChatRoomPreviewItem] {
        roomRepository.topRoomsWithPreviews.map {
            ChatRoomPreviewItem(room: $0.0, messages: $0.1)
        }
    }

    func refreshTopRooms(limit: Int = 30) async throws -> [ChatRoomPreviewItem] {
        try await roomRepository.fetchTopRoomsPage(after: nil, limit: limit)
        return cachedTopRooms()
    }

    func removeCachedRoom(roomID: String) {
        roomRepository.removeLocalRoom(roomID: roomID)
    }
}
