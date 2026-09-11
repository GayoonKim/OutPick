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
    func cachedTopRooms() async -> [ChatRoomPreviewItem]

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
    private let sanitizeCachedMessages: ([ChatMessage], String) async throws -> [ChatMessage]

    init(
        roomRepository: FirebaseChatRoomRepositoryProtocol,
        profileSyncManager: ChatProfileSyncManaging,
        sanitizeCachedMessages: @escaping ([ChatMessage], String) async throws -> [ChatMessage]
    ) {
        self.roomRepository = roomRepository
        self.profileSyncManager = profileSyncManager
        self.sanitizeCachedMessages = sanitizeCachedMessages
    }

    func cachedTopRooms() async -> [ChatRoomPreviewItem] {
        let items = await Self.resolveCachedPreviews(
            roomRepository.topRoomsWithPreviews, sanitize: sanitizeCachedMessages
        )
        return items.map { ChatRoomPreviewItem(room: $0.room, messages: overlayCurrentProfiles(on: $0.messages)) }
    }

    static func resolveCachedPreviews(
        _ rooms: [(ChatRoom, [ChatMessage])],
        sanitize: ([ChatMessage], String) async throws -> [ChatMessage]
    ) async -> [ChatRoomPreviewItem] {
        var items: [ChatRoomPreviewItem] = []
        for (room, messages) in rooms {
            guard !Task.isCancelled else { return [] }
            // 서버 재조회 없이 로컬 삭제 마커를 적용한다. 실패 시 원문으로 되돌리지 않는다.
            let sanitized = (try? await sanitize(messages, room.id)) ?? []
            items.append(ChatRoomPreviewItem(room: room, messages: sanitized))
        }
        return items
    }

    func refreshTopRooms(limit: Int = 30) async throws -> [ChatRoomPreviewItem] {
        try await roomRepository.fetchTopRoomsPage(after: nil, limit: limit)
        let messages = roomRepository.topRoomsWithPreviews.flatMap(\.1)
        _ = await profileSyncManager.refreshProfiles(from: messages)
        return await cachedTopRooms()
    }

    func refreshCachedProfiles() async -> [ChatRoomPreviewItem] {
        let messages = roomRepository.topRoomsWithPreviews.flatMap(\.1)
        _ = await profileSyncManager.refreshProfiles(from: messages)
        return await cachedTopRooms()
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
