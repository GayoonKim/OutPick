//
//  ShareLookbookContentToChatUseCase.swift
//  OutPick
//
//  Created by Codex on 6/16/26.
//

import Foundation

protocol ShareLookbookContentToChatUseCaseProtocol {
    func execute(
        messageID: String,
        sharedContent: LookbookSharedContent,
        messageText: String?,
        to room: ChatRoom
    ) async throws -> LookbookChatShareSendResult
}

extension ShareLookbookContentToChatUseCaseProtocol {
    func execute(
        messageID: String,
        sharedContent: LookbookSharedContent,
        to room: ChatRoom
    ) async throws -> LookbookChatShareSendResult {
        try await execute(
            messageID: messageID,
            sharedContent: sharedContent,
            messageText: nil,
            to: room
        )
    }
}

final class ShareLookbookContentToChatUseCase: ShareLookbookContentToChatUseCaseProtocol {
    private let repository: LookbookChatShareSendingRepositoryProtocol
    private let currentUserIDProvider: @Sendable () -> String

    init(
        repository: LookbookChatShareSendingRepositoryProtocol,
        currentUserIDProvider: @escaping @Sendable () -> String = { LoginManager.shared.canonicalUserID }
    ) {
        self.repository = repository
        self.currentUserIDProvider = currentUserIDProvider
    }

    func execute(
        messageID: String,
        sharedContent: LookbookSharedContent,
        messageText: String? = nil,
        to room: ChatRoom
    ) async throws -> LookbookChatShareSendResult {
        guard sharedContent.isValid else {
            throw LookbookChatShareError.invalidSharedContent
        }

        guard LookbookChatShareRoomPolicy.roomID(from: room) != nil else {
            throw LookbookChatShareError.invalidRoomID
        }

        guard !room.isClosed else {
            throw LookbookChatShareError.roomClosed
        }

        guard LookbookChatShareRoomPolicy.isShareable(room, currentUserID: currentUserIDProvider()) else {
            throw LookbookChatShareError.notJoined
        }

        return try await repository.sendLookbookShare(
            messageID: messageID,
            sharedContent: sharedContent,
            messageText: messageText,
            to: room
        )
    }
}
