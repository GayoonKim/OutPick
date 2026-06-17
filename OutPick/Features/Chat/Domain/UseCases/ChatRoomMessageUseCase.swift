//
//  ChatRoomMessageUseCase.swift
//  OutPick
//
//  Created by Codex on 2/11/26.
//

import Foundation
import Combine

protocol ChatRoomMessageUseCaseProtocol {
    func makeTextMessage(text: String, replyPreview: ReplyPreview?, room: ChatRoom) -> ChatMessage?
    func sendPreparedMessage(_ message: ChatMessage, room: ChatRoom)
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

struct ChatMessageSenderSnapshot: Equatable {
    let senderID: String
    let senderNickname: String
    let senderAvatarPath: String?
}

final class ChatRoomMessageUseCase: ChatRoomMessageUseCaseProtocol {
    private let messageManager: ChatMessageManaging
    private let sendingRepository: ChatMessageSendingRepositoryProtocol
    private let currentUserProvider: () -> ChatMessageSenderSnapshot
    private let messageIDProvider: () -> String
    private let dateProvider: () -> Date

    init(
        messageManager: ChatMessageManaging,
        sendingRepository: ChatMessageSendingRepositoryProtocol = SocketChatMessageSendingRepository(),
        currentUserProvider: @escaping () -> ChatMessageSenderSnapshot = {
            ChatMessageSenderSnapshot(
                senderID: LoginManager.shared.getUserEmail,
                senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "",
                senderAvatarPath: LoginManager.shared.currentUserProfile?.thumbPath
            )
        },
        messageIDProvider: @escaping () -> String = { UUID().uuidString },
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.messageManager = messageManager
        self.sendingRepository = sendingRepository
        self.currentUserProvider = currentUserProvider
        self.messageIDProvider = messageIDProvider
        self.dateProvider = dateProvider
    }

    func makeTextMessage(text: String, replyPreview: ReplyPreview?, room: ChatRoom) -> ChatMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let roomID = room.ID,
              !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let sender = currentUserProvider()
        return ChatMessage(
            ID: messageIDProvider(),
            seq: 0,
            roomID: roomID,
            senderID: sender.senderID,
            senderNickname: sender.senderNickname,
            senderAvatarPath: sender.senderAvatarPath,
            msg: trimmed,
            sentAt: dateProvider(),
            attachments: [],
            replyPreview: replyPreview
        )
    }

    func sendPreparedMessage(_ message: ChatMessage, room: ChatRoom) {
        sendingRepository.sendMessage(message, to: room)
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
