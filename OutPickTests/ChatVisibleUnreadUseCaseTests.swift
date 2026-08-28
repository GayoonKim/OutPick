import Foundation
import Testing
@testable import OutPick

struct ChatVisibleUnreadUseCaseTests {
    @Test func mixedBlockedMessagesKeepOnlyVisibleUnreadAcrossPages() async throws {
        let repository = VisibleUnreadMessageRepositoryFake(messages: [
            message(seq: 11, senderUID: "blocked", text: "B-1"),
            message(seq: 12, senderUID: "visible-c", text: "C"),
            message(seq: 13, senderUID: "blocked", text: "B-2"),
            message(seq: 14, senderUID: "visible-d", text: "D")
        ])
        let useCase = ChatVisibleUnreadUseCase(messageRepository: repository, pageSize: 2)

        let result = try await useCase.execute(
            room: room(latestSeq: 14),
            after: 10,
            through: 14,
            currentUserID: "me",
            blockedUserIDs: ["blocked"]
        )

        #expect(result.visibleUnreadCount == 2)
        #expect(result.latestVisibleMessage?.seq == 14)
        #expect(repository.requestedAfterSeqs == [10, 12])
    }

    @Test func blockedSelfAndDeletedMessagesDoNotBecomeUnread() async throws {
        var deleted = message(seq: 13, senderUID: "visible", text: "deleted")
        deleted.isDeleted = true
        let repository = VisibleUnreadMessageRepositoryFake(messages: [
            message(seq: 11, senderUID: "blocked", text: "blocked"),
            message(seq: 12, senderUID: "me", text: "mine"),
            deleted
        ])
        let useCase = ChatVisibleUnreadUseCase(messageRepository: repository, pageSize: 10)

        let result = try await useCase.execute(
            room: room(latestSeq: 13),
            after: 10,
            through: 13,
            currentUserID: "me",
            blockedUserIDs: ["blocked"]
        )

        #expect(result.visibleUnreadCount == 0)
        #expect(result.latestVisibleMessage == nil)
    }

    @Test func targetLatestSeqExcludesMessagesThatArrivedDuringSync() async throws {
        let repository = VisibleUnreadMessageRepositoryFake(messages: [
            message(seq: 11, senderUID: "visible", text: "included"),
            message(seq: 12, senderUID: "visible", text: "future")
        ])
        let useCase = ChatVisibleUnreadUseCase(messageRepository: repository, pageSize: 10)

        let result = try await useCase.execute(
            room: room(latestSeq: 12),
            after: 10,
            through: 11,
            currentUserID: "me",
            blockedUserIDs: ["blocked"]
        )

        #expect(result.visibleUnreadCount == 1)
        #expect(result.latestVisibleMessage?.seq == 11)
    }

    private func room(latestSeq: Int64) -> ChatRoom {
        var room = ChatRoom(
            id: "room",
            roomName: "room",
            roomDescription: "",
            participants: [],
            creatorUID: "owner",
            createdAt: .distantPast
        )
        room.seq = latestSeq
        return room
    }

    private func message(seq: Int64, senderUID: String, text: String) -> ChatMessage {
        ChatMessage(
            ID: "message-\(seq)",
            seq: seq,
            roomID: "room",
            senderUID: senderUID,
            senderNickname: senderUID,
            messageType: .text,
            msg: text,
            sentAt: Date(timeIntervalSince1970: TimeInterval(seq)),
            attachments: [],
            replyPreview: nil
        )
    }
}

@MainActor
struct JoinedRoomsVisibleUnreadTests {
    @Test func offlineMixedMessagesReplaceRawUnreadAndBlockedPreview() async {
        let item = joinedItem(lastReadSeq: 10, latestSeq: 13, lastSenderUID: "blocked")
        let visibleMessage = message(seq: 12, senderUID: "visible", text: "보이는 메시지")
        let visibleUnread = VisibleUnreadUseCaseFake(
            result: .success(ChatVisibleUnreadSummary(
                roomID: "room",
                latestSeq: 13,
                visibleUnreadCount: 1,
                latestVisibleMessage: visibleMessage
            ))
        )
        let viewModel = JoinedRoomsViewModel(
            useCase: VisibleUnreadJoinedRoomsUseCaseFake(item: item),
            userBlockVisibilityStore: UserBlockVisibilityStore(blockedUserIDs: ["blocked"]),
            visibleUnreadUseCase: visibleUnread
        )

        await viewModel.reloadJoinedRooms()
        await waitUntil { visibleUnread.callCount == 1 }

        #expect(viewModel.state.unreadCounts["room"] == 1)
        #expect(viewModel.state.rooms.first?.lastMessage == "보이는 메시지")
        #expect(viewModel.state.rooms.first?.lastMessageSenderUID == "visible")
    }

    @Test func syncFailureKeepsConservativeRawUnreadInsteadOfZero() async {
        let item = joinedItem(lastReadSeq: 10, latestSeq: 13, lastSenderUID: "blocked")
        let visibleUnread = VisibleUnreadUseCaseFake(result: .failure(VisibleUnreadTestError.failed))
        let viewModel = JoinedRoomsViewModel(
            useCase: VisibleUnreadJoinedRoomsUseCaseFake(item: item),
            userBlockVisibilityStore: UserBlockVisibilityStore(blockedUserIDs: ["blocked"]),
            visibleUnreadUseCase: visibleUnread
        )

        await viewModel.reloadJoinedRooms()
        await waitUntil { visibleUnread.callCount == 1 }

        #expect(viewModel.state.unreadCounts["room"] == 3)
        #expect(viewModel.state.rooms.first?.lastMessage == nil)
    }

    private func joinedItem(
        lastReadSeq: Int64,
        latestSeq: Int64,
        lastSenderUID: String
    ) -> JoinedRoomListItem {
        var room = ChatRoom(
            id: "room",
            roomName: "room",
            roomDescription: "",
            participants: [],
            creatorUID: "owner",
            createdAt: .distantPast
        )
        room.seq = latestSeq
        room.lastMessage = "차단 메시지"
        room.lastMessageSenderUID = lastSenderUID
        room.lastMessageAt = Date(timeIntervalSince1970: TimeInterval(latestSeq))
        let projection = JoinedRoomProjection(
            documentID: room.id,
            data: ["roomID": room.id, "lastReadSeq": lastReadSeq]
        )!
        return JoinedRoomListItem(room: room, projection: projection)
    }

    private func message(seq: Int64, senderUID: String, text: String) -> ChatMessage {
        ChatMessage(
            ID: "message-\(seq)",
            seq: seq,
            roomID: "room",
            senderUID: senderUID,
            senderNickname: senderUID,
            messageType: .text,
            msg: text,
            sentAt: Date(timeIntervalSince1970: TimeInterval(seq)),
            attachments: [],
            replyPreview: nil
        )
    }

    private func waitUntil(
        attempts: Int = 1_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
    }
}

private final class VisibleUnreadMessageRepositoryFake: FirebaseMessageRepositoryProtocol {
    private let messages: [ChatMessage]
    private(set) var requestedAfterSeqs: [Int64] = []

    init(messages: [ChatMessage]) {
        self.messages = messages.sorted { $0.seq < $1.seq }
    }

    func fetchMessagesAfterSeq(
        room: ChatRoom,
        afterSeq: Int64,
        limit: Int
    ) async throws -> [ChatMessage] {
        requestedAfterSeqs.append(afterSeq)
        return Array(messages.filter { $0.seq > afterSeq }.prefix(limit))
    }

    func fetchMessagesPaged(for room: ChatRoom, pageSize: Int, reset: Bool) async throws -> [ChatMessage] {
        throw VisibleUnreadTestError.unexpectedCall
    }

    func fetchLatestMessages(for room: ChatRoom, limit: Int) async throws -> [ChatMessage] {
        throw VisibleUnreadTestError.unexpectedCall
    }

    func fetchMessagesBeforeSeq(room: ChatRoom, beforeSeq: Int64, limit: Int) async throws -> [ChatMessage] {
        throw VisibleUnreadTestError.unexpectedCall
    }

    func fetchOlderMessages(for room: ChatRoom, before messageID: String, limit: Int) async throws -> [ChatMessage] {
        throw VisibleUnreadTestError.unexpectedCall
    }

    func fetchMessagesAfter(room: ChatRoom, after messageID: String, limit: Int) async throws -> [ChatMessage] {
        throw VisibleUnreadTestError.unexpectedCall
    }

    func searchMessagesInRoom(roomID: String, keyword: String) async throws -> ChatMessageServerSearchResponse {
        throw VisibleUnreadTestError.unexpectedCall
    }
}

@MainActor
private final class VisibleUnreadUseCaseFake: ChatVisibleUnreadUseCaseProtocol {
    let result: Result<ChatVisibleUnreadSummary, Error>
    private(set) var callCount = 0

    init(result: Result<ChatVisibleUnreadSummary, Error>) {
        self.result = result
    }

    func execute(
        room: ChatRoom,
        after lastReadSeq: Int64,
        through latestSeq: Int64,
        currentUserID: String,
        blockedUserIDs: Set<String>
    ) async throws -> ChatVisibleUnreadSummary {
        callCount += 1
        return try result.get()
    }
}

private final class VisibleUnreadJoinedRoomsUseCaseFake: JoinedRoomsUseCaseProtocol {
    let item: JoinedRoomListItem

    init(item: JoinedRoomListItem) {
        self.item = item
    }

    func fetchJoinedRooms(limit: Int?) async throws -> [JoinedRoomListItem] { [item] }

    func fetchUnreadCount(
        roomID: String,
        lastMessageSeqHint: Int64?,
        lastMessageSenderUID: String?
    ) async -> Int64 { 0 }

    func fetchReadSnapshot(
        roomID: String,
        lastMessageSeqHint: Int64?,
        lastMessageSenderUID: String?
    ) async -> ChatRoomReadSnapshot? { nil }

    func canLeaveFromList(room: ChatRoom) -> Bool { true }

    func leave(room: ChatRoom) async throws -> ChatRoomExitResult {
        throw VisibleUnreadTestError.unexpectedCall
    }
}

private enum VisibleUnreadTestError: Error {
    case failed
    case unexpectedCall
}
