//
//  LookbookChatShareUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 6/16/26.
//

import Combine
import FirebaseFirestore
import Foundation
import Testing
@testable import OutPick

struct LookbookChatShareUseCaseTests {
    @Test func loadShareableJoinedRoomsFiltersUnavailableRooms() async throws {
        let fake = JoinedRoomsUseCaseFake(rooms: [
            makeRoom(id: "room-1", participants: ["me@example.com"]),
            makeRoom(id: "room-2", participants: ["me@example.com"], isClosed: true),
            makeRoom(id: "room-3", participants: ["other@example.com"]),
            makeRoom(id: nil, participants: ["me@example.com"]),
            makeRoom(id: "room-4", participants: [" ME@EXAMPLE.COM "])
        ])
        let useCase = LoadShareableJoinedRoomsUseCase(
            joinedRoomsUseCase: fake,
            currentUserIDProvider: { "me@example.com" }
        )

        let rooms = try await useCase.execute(limit: 20)

        #expect(fake.requestedHeadLimits == [20])
        #expect(rooms.map { $0.ID ?? "" } == ["room-1", "room-4"])
    }

    @Test func shareLookbookContentSendsThroughRepository() async throws {
        let expected = LookbookChatShareSendResult(roomID: "room-1", messageID: "message-1", seq: 42)
        let repository = LookbookChatShareSendingRepositorySpy(result: expected)
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let content = makeSharedContent()
        let room = makeRoom(id: "room-1", participants: ["me@example.com"])

        let result = try await useCase.execute(sharedContent: content, to: room)

        #expect(result == expected)
        #expect(repository.calls.count == 1)
        #expect(repository.calls.first?.sharedContent == content)
        #expect(repository.calls.first?.messageText == nil)
        #expect(repository.calls.first?.room.ID == "room-1")
    }

    @Test func shareLookbookContentForwardsOptionalMessageText() async throws {
        let repository = LookbookChatShareSendingRepositorySpy()
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let room = makeRoom(id: "room-1", participants: ["me@example.com"])

        _ = try await useCase.execute(
            sharedContent: makeSharedContent(),
            messageText: "이 시즌 봐봐",
            to: room
        )

        #expect(repository.calls.first?.messageText == "이 시즌 봐봐")
    }

    @Test func shareLookbookContentRejectsClosedRoomBeforeSending() async {
        let repository = LookbookChatShareSendingRepositorySpy()
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let room = makeRoom(id: "room-1", participants: ["me@example.com"], isClosed: true)

        await expectShareError(.roomClosed) {
            _ = try await useCase.execute(sharedContent: makeSharedContent(), to: room)
        }
        #expect(repository.calls.isEmpty)
    }

    @Test func shareLookbookContentRejectsNonParticipantBeforeSending() async {
        let repository = LookbookChatShareSendingRepositorySpy()
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let room = makeRoom(id: "room-1", participants: ["other@example.com"])

        await expectShareError(.notJoined) {
            _ = try await useCase.execute(sharedContent: makeSharedContent(), to: room)
        }
        #expect(repository.calls.isEmpty)
    }

    @Test func shareLookbookContentRejectsInvalidContentBeforeSending() async {
        let repository = LookbookChatShareSendingRepositorySpy()
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let invalidContent = LookbookSharedContent(
            schemaVersion: 1,
            contentType: .post,
            brandID: "brand-1",
            seasonID: nil,
            postID: "post-1",
            titleSnapshot: "포스트"
        )

        await expectShareError(.invalidSharedContent) {
            _ = try await useCase.execute(
                sharedContent: invalidContent,
                to: makeRoom(id: "room-1", participants: ["me@example.com"])
            )
        }
        #expect(repository.calls.isEmpty)
    }

    @Test func ackMapperParsesSuccessAck() throws {
        let result = try LookbookChatShareAckMapper.parse(
            [["ok": true, "messageID": "server-message", "seq": 42]],
            roomID: "room-1",
            fallbackMessageID: "client-message"
        )

        #expect(result == LookbookChatShareSendResult(
            roomID: "room-1",
            messageID: "server-message",
            seq: 42
        ))
    }

    @Test func ackMapperMapsFailureCodes() {
        expectAckError(.notJoined) {
            _ = try LookbookChatShareAckMapper.parse(
                [["ok": false, "error": "not_joined"]],
                roomID: "room-1",
                fallbackMessageID: "client-message"
            )
        }

        expectAckError(.roomClosed) {
            _ = try LookbookChatShareAckMapper.parse(
                [["ok": false, "error": "room_closed"]],
                roomID: "room-1",
                fallbackMessageID: "client-message"
            )
        }

        expectAckError(.timeout) {
            _ = try LookbookChatShareAckMapper.parse(
                ["NO ACK"],
                roomID: "room-1",
                fallbackMessageID: "client-message"
            )
        }
    }

    private func expectShareError(
        _ expected: LookbookChatShareError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            #expect(Bool(false), "Expected \(expected)")
        } catch let error as LookbookChatShareError {
            #expect(error == expected)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    private func expectAckError(
        _ expected: LookbookChatShareError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            #expect(Bool(false), "Expected \(expected)")
        } catch let error as LookbookChatShareError {
            #expect(error == expected)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    private func makeSharedContent() -> LookbookSharedContent {
        LookbookSharedContent(
            schemaVersion: 1,
            contentType: .season,
            brandID: "brand-1",
            seasonID: "season-1",
            titleSnapshot: "2026 Summer",
            subtitleSnapshot: "Brand"
        )
    }

    private func makeRoom(
        id: String?,
        participants: [String],
        isClosed: Bool = false
    ) -> ChatRoom {
        ChatRoom(
            ID: id,
            roomName: "Test Room",
            roomDescription: "Test Description",
            participants: participants,
            creatorID: "owner@example.com",
            createdAt: Date(timeIntervalSince1970: 0),
            thumbPath: nil,
            originalPath: nil,
            lastMessageAt: nil,
            lastMessage: nil,
            lastMessageSenderID: nil,
            seq: 0,
            isClosed: isClosed,
            activeAnnouncementID: nil,
            activeAnnouncement: nil,
            announcementUpdatedAt: nil
        )
    }
}

private final class JoinedRoomsUseCaseFake: JoinedRoomsUseCaseProtocol {
    let joinedRoomsPublisher: AnyPublisher<[ChatRoom], Never>
    private let rooms: [ChatRoom]
    private(set) var requestedHeadLimits: [Int] = []

    init(rooms: [ChatRoom]) {
        self.rooms = rooms
        self.joinedRoomsPublisher = Just(rooms).eraseToAnyPublisher()
    }

    func fetchJoinedRoomsHead(limit: Int) async throws -> (rooms: [ChatRoom], cursor: DocumentSnapshot?) {
        requestedHeadLimits.append(limit)
        return (rooms, nil)
    }

    func loadMoreJoinedRooms(after cursor: DocumentSnapshot?, limit: Int) async throws -> (rooms: [ChatRoom], cursor: DocumentSnapshot?) {
        ([], nil)
    }

    func syncJoinedRoomsTail(since: Date, limit: Int) async throws -> [ChatRoom] {
        []
    }

    @MainActor
    func startRoomUpdates(limit: Int) {}

    @MainActor
    func stopRoomUpdates() {}

    func fetchUnreadCount(roomID: String, lastMessageSeqHint: Int64?, lastMessageSenderID: String?) async -> Int64 {
        0
    }

    func leave(room: ChatRoom) {}
}

private final class LookbookChatShareSendingRepositorySpy: LookbookChatShareSendingRepositoryProtocol {
    struct Call {
        let sharedContent: LookbookSharedContent
        let messageText: String?
        let room: ChatRoom
    }

    private let result: LookbookChatShareSendResult
    var error: Error?
    private(set) var calls: [Call] = []

    init(
        result: LookbookChatShareSendResult = LookbookChatShareSendResult(
            roomID: "room-1",
            messageID: "message-1",
            seq: nil
        )
    ) {
        self.result = result
    }

    func sendLookbookShare(
        sharedContent: LookbookSharedContent,
        messageText: String?,
        to room: ChatRoom
    ) async throws -> LookbookChatShareSendResult {
        calls.append(Call(sharedContent: sharedContent, messageText: messageText, room: room))
        if let error {
            throw error
        }
        return result
    }
}
