//
//  ChatRoomRealtimeUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 6/17/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatRoomRealtimeUseCaseTests {
    @Test func openMessageStreamDelegatesRoomIDAndExposesMessages() async throws {
        let message = makeMessage(id: "message-1", roomID: "room-1")
        let repository = ChatRoomRealtimeRepositoryFake(messages: [message])
        let useCase = ChatRoomRealtimeUseCase(repository: repository)

        let session = try await useCase.openMessageStream(roomID: "room-1")
        var iterator = session.messages.makeAsyncIterator()
        let receivedMessage = await iterator.next()

        #expect(repository.requestedRoomIDs == ["room-1"])
        #expect(session.roomID == "room-1")
        #expect(receivedMessage?.ID == "message-1")
        #expect(receivedMessage?.roomID == "room-1")
    }

    private func makeMessage(id: String, roomID: String) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: 1,
            roomID: roomID,
            senderID: "sender@example.com",
            senderNickname: "Sender",
            senderAvatarPath: nil,
            msg: "안녕",
            sentAt: Date(timeIntervalSince1970: 123),
            attachments: [],
            replyPreview: nil
        )
    }
}

private final class ChatRoomRealtimeRepositoryFake: ChatRoomRealtimeRepositoryProtocol {
    private let messages: [ChatMessage]
    private(set) var requestedRoomIDs: [String] = []

    init(messages: [ChatMessage]) {
        self.messages = messages
    }

    func openMessageStream(roomID: String) async throws -> ChatRoomRealtimeSession {
        requestedRoomIDs.append(roomID)

        let stream = AsyncStream<ChatMessage> { continuation in
            for message in messages {
                continuation.yield(message)
            }
            continuation.finish()
        }

        return ChatRoomRealtimeSession(
            roomID: roomID,
            messages: stream,
            close: {}
        )
    }
}
