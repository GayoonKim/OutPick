//
//  ChatRoomMessageUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 6/17/26.
//

import Combine
import Foundation
import Testing
@testable import OutPick

struct ChatRoomMessageUseCaseTests {
    @Test func makeTextMessageTrimsTextAndUsesInjectedSenderSnapshot() throws {
        let repository = ChatMessageSendingRepositorySpy()
        let useCase = makeUseCase(repository: repository)
        let replyPreview = ReplyPreview(messageID: "reply-1", sender: "상대", text: "이전 메시지")

        let message = try #require(useCase.makeTextMessage(
            text: "  안녕  ",
            replyPreview: replyPreview,
            room: makeRoom(id: "room-1")
        ))

        #expect(message.ID == "message-1")
        #expect(message.seq == 0)
        #expect(message.roomID == "room-1")
        #expect(message.senderUID == "me@example.com")
        #expect(message.senderNickname == "나")
        #expect(message.senderAvatarPath == "avatars/me.jpg")
        #expect(message.msg == "안녕")
        #expect(message.sentAt == Date(timeIntervalSince1970: 123))
        #expect(message.attachments.isEmpty)
        #expect(message.replyPreview == replyPreview)
        #expect(repository.calls.isEmpty)
    }

    @Test func makeTextMessageRejectsBlankTextOrMissingRoomID() {
        let useCase = makeUseCase()

        #expect(useCase.makeTextMessage(text: "   ", replyPreview: nil, room: makeRoom(id: "room-1")) == nil)
        #expect(useCase.makeTextMessage(text: "안녕", replyPreview: nil, room: makeRoom(id: "")) == nil)
        #expect(useCase.makeTextMessage(text: "안녕", replyPreview: nil, room: makeRoom(id: "   ")) == nil)
    }

    @Test func sendPreparedMessageDelegatesToRepository() async throws {
        let repository = ChatMessageSendingRepositorySpy()
        let useCase = makeUseCase(repository: repository)
        let room = makeRoom(id: "room-1")
        let message = try #require(useCase.makeTextMessage(text: "안녕", replyPreview: nil, room: room))

        try await useCase.sendPreparedMessage(message, room: room)

        #expect(repository.calls.count == 1)
        #expect(repository.calls.first?.message.ID == "message-1")
        #expect(repository.calls.first?.room.id == "room-1")
    }

    @Test func deleteMessageUpdatesDeletedLastMessageSummaryWhenMessageHasSeq() async throws {
        let messageManager = ChatMessageDeleteManagerSpy()
        let summaryUpdater = DeletedLastMessageSummaryUpdaterSpy()
        let useCase = makeUseCase(
            messageManager: messageManager,
            deletedLastMessageSummaryUpdater: summaryUpdater
        )
        let room = makeRoom(id: "room-1")
        let message = makeMessage(id: "message-1", roomID: "room-1", seq: 7)

        try await useCase.deleteMessage(message: message, room: room)

        #expect(messageManager.deletedMessages.map(\.ID) == ["message-1"])
        #expect(summaryUpdater.calls.count == 1)
        #expect(summaryUpdater.calls.first?.roomID == "room-1")
        #expect(summaryUpdater.calls.first?.deletedMessageSeq == 7)
        #expect(summaryUpdater.calls.first?.deletedPreview == "삭제된 메시지입니다.")
    }

    @Test func deleteMessageSkipsSummaryUpdateWhenMessageSeqIsMissing() async throws {
        let messageManager = ChatMessageDeleteManagerSpy()
        let summaryUpdater = DeletedLastMessageSummaryUpdaterSpy()
        let useCase = makeUseCase(
            messageManager: messageManager,
            deletedLastMessageSummaryUpdater: summaryUpdater
        )
        let room = makeRoom(id: "room-1")
        let message = makeMessage(id: "message-1", roomID: "room-1", seq: 0)

        try await useCase.deleteMessage(message: message, room: room)

        #expect(messageManager.deletedMessages.map(\.ID) == ["message-1"])
        #expect(summaryUpdater.calls.isEmpty)
    }

    private func makeUseCase(
        messageManager: ChatMessageManaging = ChatMessageManagerStub(),
        repository: ChatMessageSendingRepositorySpy = ChatMessageSendingRepositorySpy(),
        deletedLastMessageSummaryUpdater: ChatDeletedLastMessageSummaryUpdating? = nil
    ) -> ChatRoomMessageUseCase {
        ChatRoomMessageUseCase(
            messageManager: messageManager,
            sendingRepository: repository,
            deletedLastMessageSummaryUpdater: deletedLastMessageSummaryUpdater,
            currentUserProvider: {
                ChatMessageSenderSnapshot(
                    senderUID: "me@example.com",
                    senderEmail: nil,
                    senderNickname: "나",
                    senderAvatarPath: "avatars/me.jpg"
                )
            },
            messageIDProvider: { "message-1" },
            dateProvider: { Date(timeIntervalSince1970: 123) }
        )
    }

    private func makeRoom(id: String) -> ChatRoom {
        ChatRoom(
            id: id,
            roomName: "Test Room",
            roomDescription: "Test Description",
            participants: ["me@example.com"],
            creatorUID: "owner@example.com",
            createdAt: Date(timeIntervalSince1970: 0),
            thumbPath: nil,
            originalPath: nil,
            lastMessageAt: nil,
            lastMessage: nil,
            lastMessageSenderUID: nil,
            seq: 0,
            isClosed: false,
            activeAnnouncementID: nil,
            activeAnnouncement: nil,
            announcementUpdatedAt: nil
        )
    }

    private func makeMessage(id: String, roomID: String, seq: Int64) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: seq,
            roomID: roomID,
            senderUID: "me@example.com",
            senderEmail: nil,
            senderNickname: "나",
            senderAvatarPath: nil,
            msg: "삭제할 메시지",
            sentAt: Date(timeIntervalSince1970: 123),
            attachments: [],
            replyPreview: nil
        )
    }
}

private final class ChatMessageSendingRepositorySpy: ChatMessageSendingRepositoryProtocol {
    struct Call {
        let message: ChatMessage
        let room: ChatRoom
    }

    private(set) var calls: [Call] = []

    func sendMessage(_ message: ChatMessage, to room: ChatRoom) async throws {
        calls.append(Call(message: message, room: room))
    }
}

private final class ChatMessageManagerStub: ChatMessageManaging {
    func loadLocalInitialWindow(
        roomID: String,
        mode: ChatInitialOpenMode,
        policy: ChatInitialLoadPolicy
    ) async throws -> ChatInitialWindow {
        throw StubError.unimplemented
    }

    func fetchServerInitialWindow(
        room: ChatRoom,
        mode: ChatInitialOpenMode,
        policy: ChatInitialLoadPolicy
    ) async throws -> ChatInitialWindow {
        throw StubError.unimplemented
    }

    func persistFetchedServerMessages(_ messages: [ChatMessage]) async throws {
        throw StubError.unimplemented
    }

    func loadMessagesAroundAnchor(
        room: ChatRoom,
        anchor: ChatMessage,
        beforeLimit: Int,
        afterLimit: Int
    ) async throws -> [ChatMessage] {
        throw StubError.unimplemented
    }

    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage] {
        throw StubError.unimplemented
    }

    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage] {
        throw StubError.unimplemented
    }

    func syncDeletedStates(localMessages: [ChatMessage], room: ChatRoom) async throws -> [String] {
        throw StubError.unimplemented
    }

    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws {
        throw StubError.unimplemented
    }

    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        throw StubError.unimplemented
    }

    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable {
        AnyCancellable {}
    }

    func saveMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        throw StubError.unimplemented
    }

    private enum StubError: Error {
        case unimplemented
    }
}

private final class ChatMessageDeleteManagerSpy: ChatMessageManaging {
    private(set) var deletedMessages: [ChatMessage] = []
    private(set) var deletedRooms: [ChatRoom] = []

    func loadLocalInitialWindow(
        roomID: String,
        mode: ChatInitialOpenMode,
        policy: ChatInitialLoadPolicy
    ) async throws -> ChatInitialWindow {
        throw StubError.unimplemented
    }

    func fetchServerInitialWindow(
        room: ChatRoom,
        mode: ChatInitialOpenMode,
        policy: ChatInitialLoadPolicy
    ) async throws -> ChatInitialWindow {
        throw StubError.unimplemented
    }

    func persistFetchedServerMessages(_ messages: [ChatMessage]) async throws {
        throw StubError.unimplemented
    }

    func loadMessagesAroundAnchor(
        room: ChatRoom,
        anchor: ChatMessage,
        beforeLimit: Int,
        afterLimit: Int
    ) async throws -> [ChatMessage] {
        throw StubError.unimplemented
    }

    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage] {
        throw StubError.unimplemented
    }

    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage] {
        throw StubError.unimplemented
    }

    func syncDeletedStates(localMessages: [ChatMessage], room: ChatRoom) async throws -> [String] {
        throw StubError.unimplemented
    }

    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws {
        deletedMessages.append(message)
        deletedRooms.append(room)
    }

    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        throw StubError.unimplemented
    }

    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable {
        AnyCancellable {}
    }

    func saveMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        throw StubError.unimplemented
    }

    private enum StubError: Error {
        case unimplemented
    }
}

private final class DeletedLastMessageSummaryUpdaterSpy: ChatDeletedLastMessageSummaryUpdating {
    struct Call {
        let roomID: String
        let deletedMessageSeq: Int64
        let deletedPreview: String
    }

    private(set) var calls: [Call] = []

    func updateDeletedLastMessageSummaryIfCurrent(
        roomID: String,
        deletedMessageSeq: Int64,
        deletedPreview: String
    ) async throws {
        calls.append(
            Call(
                roomID: roomID,
                deletedMessageSeq: deletedMessageSeq,
                deletedPreview: deletedPreview
            )
        )
    }
}
