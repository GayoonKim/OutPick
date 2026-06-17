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
        #expect(message.senderID == "me@example.com")
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
        #expect(useCase.makeTextMessage(text: "안녕", replyPreview: nil, room: makeRoom(id: nil)) == nil)
        #expect(useCase.makeTextMessage(text: "안녕", replyPreview: nil, room: makeRoom(id: "   ")) == nil)
    }

    @Test func sendPreparedMessageDelegatesToRepository() throws {
        let repository = ChatMessageSendingRepositorySpy()
        let useCase = makeUseCase(repository: repository)
        let room = makeRoom(id: "room-1")
        let message = try #require(useCase.makeTextMessage(text: "안녕", replyPreview: nil, room: room))

        useCase.sendPreparedMessage(message, room: room)

        #expect(repository.calls.count == 1)
        #expect(repository.calls.first?.message.ID == "message-1")
        #expect(repository.calls.first?.room.ID == "room-1")
    }

    private func makeUseCase(
        repository: ChatMessageSendingRepositorySpy = ChatMessageSendingRepositorySpy()
    ) -> ChatRoomMessageUseCase {
        ChatRoomMessageUseCase(
            messageManager: ChatMessageManagerStub(),
            sendingRepository: repository,
            currentUserProvider: {
                ChatMessageSenderSnapshot(
                    senderID: "me@example.com",
                    senderNickname: "나",
                    senderAvatarPath: "avatars/me.jpg"
                )
            },
            messageIDProvider: { "message-1" },
            dateProvider: { Date(timeIntervalSince1970: 123) }
        )
    }

    private func makeRoom(id: String?) -> ChatRoom {
        ChatRoom(
            ID: id,
            roomName: "Test Room",
            roomDescription: "Test Description",
            participants: ["me@example.com"],
            creatorID: "owner@example.com",
            createdAt: Date(timeIntervalSince1970: 0),
            thumbPath: nil,
            originalPath: nil,
            lastMessageAt: nil,
            lastMessage: nil,
            lastMessageSenderID: nil,
            seq: 0,
            isClosed: false,
            activeAnnouncementID: nil,
            activeAnnouncement: nil,
            announcementUpdatedAt: nil
        )
    }
}

private final class ChatMessageSendingRepositorySpy: ChatMessageSendingRepositoryProtocol {
    struct Call {
        let message: ChatMessage
        let room: ChatRoom
    }

    private(set) var calls: [Call] = []

    func sendMessage(_ message: ChatMessage, to room: ChatRoom) {
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
