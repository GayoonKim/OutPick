//
//  ChatRoomMessageUseCase.swift
//  OutPick
//
//  Created by Codex on 2/11/26.
//

import Foundation
import Combine

protocol ChatRoomMessageUseCaseProtocol {
    func loadInitialMessages(room: ChatRoom, isParticipant: Bool) async throws -> (local: [ChatMessage], server: [ChatMessage])
    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage]
    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage]
    func syncDeletedStates(localMessages: [ChatMessage], room: ChatRoom) async throws -> [String]
    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws
    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable
    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws
}

final class ChatRoomMessageUseCase: ChatRoomMessageUseCaseProtocol {
    private let messageManager: ChatMessageManaging

    init(messageManager: ChatMessageManaging) {
        self.messageManager = messageManager
    }

    func loadInitialMessages(room: ChatRoom, isParticipant: Bool) async throws -> (local: [ChatMessage], server: [ChatMessage]) {
        try await messageManager.loadInitialMessages(room: room, isParticipant: isParticipant)
    }

    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage] {
        try await messageManager.loadOlderMessages(room: room, before: messageID)
    }

    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage] {
        try await messageManager.loadNewerMessages(room: room, after: messageID)
    }

    func syncDeletedStates(localMessages: [ChatMessage], room: ChatRoom) async throws -> [String] {
        try await messageManager.syncDeletedStates(localMessages: localMessages, room: room)
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
