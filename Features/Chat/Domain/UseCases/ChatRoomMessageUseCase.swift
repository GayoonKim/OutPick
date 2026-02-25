//
//  ChatRoomMessageUseCase.swift
//  OutPick
//
//  Created by Codex on 2/11/26.
//

import Foundation
import Combine

protocol ChatRoomMessageUseCaseProtocol {
    func loadMessagesAroundAnchor(
        room: ChatRoom,
        anchor: ChatMessage,
        beforeLimit: Int,
        afterLimit: Int
    ) async throws -> [ChatMessage]
    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage]
    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage]
    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws
    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable
    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws
}

final class ChatRoomMessageUseCase: ChatRoomMessageUseCaseProtocol {
    private let messageManager: ChatMessageManaging

    init(messageManager: ChatMessageManaging) {
        self.messageManager = messageManager
    }

    func loadMessagesAroundAnchor(
        room: ChatRoom,
        anchor: ChatMessage,
        beforeLimit: Int,
        afterLimit: Int
    ) async throws -> [ChatMessage] {
        try await messageManager.loadMessagesAroundAnchor(
            room: room,
            anchor: anchor,
            beforeLimit: beforeLimit,
            afterLimit: afterLimit
        )
    }

    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage] {
        try await messageManager.loadOlderMessages(room: room, before: messageID)
    }

    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage] {
        try await messageManager.loadNewerMessages(room: room, after: messageID)
    }

    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        try await messageManager.handleIncomingMessage(message, room: room)
    }

    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable {
        messageManager.setupDeletionListener(roomID: roomID, onDeleted: onDeleted)
    }

    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws {
        try await messageManager.deleteMessage(message: message, room: room)
    }
}
