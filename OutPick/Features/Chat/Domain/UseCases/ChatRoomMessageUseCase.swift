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
    func sendPreparedMessage(
        _ message: ChatMessage,
        room: ChatRoom
    ) async throws -> ChatMessageSendReceipt
    func loadMessagesAroundAnchor(
        room: ChatRoom,
        anchor: ChatMessage,
        beforeLimit: Int,
        afterLimit: Int
    ) async throws -> [ChatMessage]
    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage]
    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage]
    func loadLatestMessageWindow(room: ChatRoom, targetSeq: Int64) async throws -> ChatLatestMessageWindow
    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws
    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable
    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws
}

protocol ChatDeletedLastMessageSummaryUpdating {
    func updateDeletedLastMessageSummaryIfCurrent(
        roomID: String,
        deletedMessageSeq: Int64,
        deletedPreview: String
    ) async throws
}

struct ChatMessageSenderSnapshot: Equatable {
    let senderUID: String
    let senderEmail: String?
    let senderNickname: String
    let senderAvatarPath: String?
}

final class ChatRoomMessageUseCase: ChatRoomMessageUseCaseProtocol {
    private static let deletedMessagePreview = "삭제된 메시지입니다."

    private let messageManager: ChatMessageManaging
    private let sendingRepository: ChatMessageSendingRepositoryProtocol
    private let deletedLastMessageSummaryUpdater: ChatDeletedLastMessageSummaryUpdating?
    private let serverConfirmedMessageReconciler: ChatServerConfirmedMessageReconciling?
    private let currentUserProvider: () -> ChatMessageSenderSnapshot
    private let messageIDProvider: () -> String
    private let dateProvider: () -> Date

    init(
        messageManager: ChatMessageManaging,
        sendingRepository: ChatMessageSendingRepositoryProtocol = SocketChatMessageSendingRepository(),
        deletedLastMessageSummaryUpdater: ChatDeletedLastMessageSummaryUpdating? = FirebaseRepositoryProvider.shared.chatRoomRepository as? ChatDeletedLastMessageSummaryUpdating,
        serverConfirmedMessageReconciler: ChatServerConfirmedMessageReconciling? = nil,
        currentUserProvider: @escaping () -> ChatMessageSenderSnapshot = {
            ChatMessageSenderSnapshot(
                senderUID: LoginManager.shared.canonicalUserID,
                senderEmail: LoginManager.shared.getUserEmail,
                senderNickname: "",
                senderAvatarPath: nil
            )
        },
        messageIDProvider: @escaping () -> String = { UUID().uuidString },
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.messageManager = messageManager
        self.sendingRepository = sendingRepository
        self.deletedLastMessageSummaryUpdater = deletedLastMessageSummaryUpdater
        self.serverConfirmedMessageReconciler = serverConfirmedMessageReconciler
        self.currentUserProvider = currentUserProvider
        self.messageIDProvider = messageIDProvider
        self.dateProvider = dateProvider
    }

    func makeTextMessage(text: String, replyPreview: ReplyPreview?, room: ChatRoom) -> ChatMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomID = room.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !roomID.isEmpty else {
            return nil
        }

        let sender = currentUserProvider()
        return ChatMessage(
            ID: messageIDProvider(),
            seq: 0,
            roomID: roomID,
            senderUID: sender.senderUID,
            senderEmail: sender.senderEmail,
            senderNickname: sender.senderNickname,
            senderAvatarPath: sender.senderAvatarPath,
            msg: trimmed,
            sentAt: dateProvider(),
            attachments: [],
            replyPreview: replyPreview
        )
    }

    func sendPreparedMessage(
        _ message: ChatMessage,
        room: ChatRoom
    ) async throws -> ChatMessageSendReceipt {
        try await sendingRepository.sendMessage(message, to: room)
    }

    func loadMessagesAroundAnchor(
        room: ChatRoom,
        anchor: ChatMessage,
        beforeLimit: Int,
        afterLimit: Int
    ) async throws -> [ChatMessage] {
        let messages = try await messageManager.loadMessagesAroundAnchor(
            room: room,
            anchor: anchor,
            beforeLimit: beforeLimit,
            afterLimit: afterLimit
        )
        try await serverConfirmedMessageReconciler?.reconcileServerConfirmedMessages(messages)
        return messages
    }

    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage] {
        let messages = try await messageManager.loadOlderMessages(room: room, before: messageID)
        try await serverConfirmedMessageReconciler?.reconcileServerConfirmedMessages(messages)
        return messages
    }

    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage] {
        let messages = try await messageManager.loadNewerMessages(room: room, after: messageID)
        try await serverConfirmedMessageReconciler?.reconcileServerConfirmedMessages(messages)
        return messages
    }

    func loadLatestMessageWindow(room: ChatRoom, targetSeq: Int64) async throws -> ChatLatestMessageWindow {
        let window = try await messageManager.loadLatestMessageWindow(room: room, targetSeq: targetSeq)
        try await serverConfirmedMessageReconciler?.reconcileServerConfirmedMessages(window.messages)
        return window
    }

    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        try await messageManager.handleIncomingMessage(message, room: room)
        try await serverConfirmedMessageReconciler?.reconcileServerConfirmedMessages([message])
    }

    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable {
        messageManager.setupDeletionListener(roomID: roomID, onDeleted: onDeleted)
    }

    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws {
        try await messageManager.deleteMessage(message: message, room: room)
        try await updateDeletedLastMessageSummaryIfNeeded(message: message, room: room)
    }

    private func updateDeletedLastMessageSummaryIfNeeded(message: ChatMessage, room: ChatRoom) async throws {
        guard let deletedLastMessageSummaryUpdater else { return }
        let roomID = room.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomID.isEmpty, message.seq > 0 else {
            return
        }

        try await deletedLastMessageSummaryUpdater.updateDeletedLastMessageSummaryIfCurrent(
            roomID: roomID,
            deletedMessageSeq: message.seq,
            deletedPreview: Self.deletedMessagePreview
        )
    }
}
