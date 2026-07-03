//
//  LoadShareableJoinedRoomsUseCase.swift
//  OutPick
//
//  Created by Codex on 6/16/26.
//

import Foundation

protocol LoadShareableJoinedRoomsUseCaseProtocol {
    func execute(limit: Int) async throws -> [ChatRoom]
}

final class LoadShareableJoinedRoomsUseCase: LoadShareableJoinedRoomsUseCaseProtocol {
    private let joinedRoomsUseCase: JoinedRoomsUseCaseProtocol
    private let currentUserIDProvider: @Sendable () -> String

    init(
        joinedRoomsUseCase: JoinedRoomsUseCaseProtocol,
        currentUserIDProvider: @escaping @Sendable () -> String = { LoginManager.shared.canonicalUserID }
    ) {
        self.joinedRoomsUseCase = joinedRoomsUseCase
        self.currentUserIDProvider = currentUserIDProvider
    }

    func execute(limit: Int = 50) async throws -> [ChatRoom] {
        let boundedLimit = max(1, limit)
        let currentUserID = currentUserIDProvider()
        let items = try await joinedRoomsUseCase.fetchJoinedRooms(limit: boundedLimit)

        return items.map(\.room)
            .filter {
                LookbookChatShareRoomPolicy.isShareable($0, currentUserID: currentUserID)
            }
            .sorted {
                ($0.lastMessageAt ?? $0.createdAt) > ($1.lastMessageAt ?? $1.createdAt)
            }
    }
}

enum LookbookChatShareRoomPolicy {
    static func roomID(from room: ChatRoom) -> String? {
        trimmedNonEmpty(room.ID)
    }

    static func isShareable(_ room: ChatRoom, currentUserID: String) -> Bool {
        guard roomID(from: room) != nil else { return false }
        guard !room.isClosed else { return false }

        return true
    }

    static func normalizedIdentifier(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
