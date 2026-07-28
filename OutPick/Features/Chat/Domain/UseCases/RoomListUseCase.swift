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

enum RoomPreviewProfileOverlay {
    static func apply(
        to messages: [ChatMessage],
        profileForUserID: (String) -> LocalChatUser?
    ) -> [ChatMessage] {
        messages.map { message in
            guard let profile = profileForUserID(message.senderUID) else {
                return message
            }

            var resolved = message
            let nickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if nickname.isEmpty == false {
                resolved.senderNickname = nickname
            }
            resolved.senderAvatarPath = profile.profileImagePath
            return resolved
        }
    }
}

protocol RoomListUseCaseProtocol {
    @MainActor
    func cachedTopRooms() -> [ChatRoomPreviewItem]

    @MainActor
    func refreshTopRooms(limit: Int) async throws -> [ChatRoomPreviewItem]

    @MainActor
    func refreshCachedProfiles() async -> [ChatRoomPreviewItem]

    @MainActor
    func removeCachedRoom(roomID: String)
}

@MainActor
final class RoomListUseCase: RoomListUseCaseProtocol {
    private let roomRepository: FirebaseChatRoomRepositoryProtocol
    private let profileSyncManager: ChatProfileSyncManaging

    init(
        roomRepository: FirebaseChatRoomRepositoryProtocol,
        profileSyncManager: ChatProfileSyncManaging
    ) {
        self.roomRepository = roomRepository
        self.profileSyncManager = profileSyncManager
    }

    func cachedTopRooms() -> [ChatRoomPreviewItem] {
        roomRepository.topRoomsWithPreviews.map {
            ChatRoomPreviewItem(
                room: $0.0,
                messages: overlayCurrentProfiles(on: $0.1)
            )
        }
    }

    func refreshTopRooms(limit: Int = 30) async throws -> [ChatRoomPreviewItem] {
        try await roomRepository.fetchTopRoomsPage(after: nil, limit: limit)
        let messages = roomRepository.topRoomsWithPreviews.flatMap(\.1)
        _ = await profileSyncManager.refreshProfiles(from: messages)
        return cachedTopRooms()
    }

    func refreshCachedProfiles() async -> [ChatRoomPreviewItem] {
        let messages = roomRepository.topRoomsWithPreviews.flatMap(\.1)
        _ = await profileSyncManager.refreshProfiles(from: messages)
        return cachedTopRooms()
    }

    func removeCachedRoom(roomID: String) {
        roomRepository.removeLocalRoom(roomID: roomID)
    }

    private func overlayCurrentProfiles(on messages: [ChatMessage]) -> [ChatMessage] {
        RoomPreviewProfileOverlay.apply(to: messages) { [profileSyncManager] userID in
            profileSyncManager.profile(for: userID)
        }
    }
}
