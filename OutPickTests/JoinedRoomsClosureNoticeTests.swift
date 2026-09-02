import Foundation
import Testing
@testable import OutPick

@MainActor
struct JoinedRoomsClosureNoticeTests {
    @Test func noticeUsesRoomNameAndFriendlyWording() {
        let ownerNotice = notice(type: .closedByOwner)
        let moderationNotice = notice(type: .closedByModeration)

        #expect(ownerNotice.title == "“QA 채팅방” 채팅방이 종료됐어요")
        #expect(ownerNotice.message == "방장이 채팅방을 종료했어요.")
        #expect(moderationNotice.message == "운영 정책에 따라 이용이 종료됐어요.")
    }

    @Test func deletedOwnerNoticeExplainsWhyTheRoomClosed() {
        let notice = ChatRoomClosureNotice(
            roomID: "room-1",
            roomName: "QA 채팅방",
            closureType: .closedByOwner,
            noticeCode: "ownerDeleted",
            closedAt: Date(timeIntervalSince1970: 1)
        )

        #expect(notice.message == "방장이 없어 방이 종료됐어요.")
    }

    @Test func acknowledgedNoticeIsNotRestoredByLaterStaleFetch() async throws {
        let repository = ClosureNoticeRepositoryFake(notices: [notice(type: .closedByOwner)])
        let viewModel = JoinedRoomsViewModel(
            useCase: EmptyJoinedRoomsUseCaseFake(),
            moderationLifecycleRepository: repository
        )

        viewModel.start()
        await waitUntil { viewModel.state.closureNotices.count == 1 }
        let loadedNotice = try #require(viewModel.state.closureNotices.first)

        try await viewModel.acknowledgeClosureNotice(loadedNotice)
        viewModel.start()
        await waitUntil { repository.fetchCount >= 2 }

        #expect(viewModel.state.closureNotices.isEmpty)
        #expect(repository.acknowledgedRoomIDs == ["room-1"])
        viewModel.stop()
    }

    @Test func realtimeClosedRoomIsNotRestoredByStaleJoinedRoomsReload() async {
        let room = closedRoom()
        let useCase = StaleJoinedRoomsUseCaseFake(room: room)
        let viewModel = JoinedRoomsViewModel(useCase: useCase)

        await viewModel.reloadJoinedRooms()
        #expect(viewModel.state.rooms.map(\.id) == ["room-1"])

        viewModel.removeRoomAfterRealtimeClosure(roomID: "room-1")
        #expect(viewModel.state.rooms.isEmpty)

        await viewModel.reloadJoinedRooms()
        #expect(viewModel.state.rooms.isEmpty)
    }

    @Test func offlineConfirmationIsOptimistic() async throws {
        let room = closedRoom()
        let acknowledgement = DeferredClosureAcknowledgementFake()
        let viewModel = JoinedRoomsViewModel(
            useCase: StaleJoinedRoomsUseCaseFake(room: room),
            closureAcknowledgementUseCase: acknowledgement
        )

        await viewModel.reloadJoinedRooms()
        let acknowledgementTask = Task {
            try await viewModel.acknowledgeClosedRoom(room)
        }
        await waitUntil { acknowledgement.hasPendingRequest }

        #expect(viewModel.state.rooms.isEmpty)
        await viewModel.reloadJoinedRooms()
        #expect(viewModel.state.rooms.isEmpty)

        acknowledgement.complete()
        try await acknowledgementTask.value
    }

    @Test func offlineConfirmationFailureRestoresRoom() async {
        let room = closedRoom()
        let acknowledgement = DeferredClosureAcknowledgementFake()
        let viewModel = JoinedRoomsViewModel(
            useCase: StaleJoinedRoomsUseCaseFake(room: room),
            closureAcknowledgementUseCase: acknowledgement
        )

        await viewModel.reloadJoinedRooms()
        let acknowledgementTask = Task {
            try await viewModel.acknowledgeClosedRoom(room)
        }
        await waitUntil { acknowledgement.hasPendingRequest }
        #expect(viewModel.state.rooms.isEmpty)

        acknowledgement.fail()
        do {
            try await acknowledgementTask.value
            Issue.record("서버 확인 실패가 호출자에게 전달되어야 합니다.")
        } catch {
            #expect(viewModel.state.rooms.map(\.id) == ["room-1"])
        }
    }

    private func closedRoom() -> ChatRoom {
        ChatRoom(
            id: "room-1",
            roomName: "QA 채팅방",
            roomDescription: "",
            participants: ["member-1"],
            creatorUID: "owner-1",
            createdAt: Date(timeIntervalSince1970: 1),
            isClosed: true,
            closureType: .closedByModeration
        )
    }

    private static func notice(type: ChatRoomClosureType) -> ChatRoomClosureNotice {
        ChatRoomClosureNotice(
            roomID: "room-1",
            roomName: "QA 채팅방",
            closureType: type,
            noticeCode: "notice-code",
            closedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func notice(type: ChatRoomClosureType) -> ChatRoomClosureNotice {
        Self.notice(type: type)
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

@MainActor
private final class ClosureNoticeRepositoryFake: ChatModerationLifecycleRepositoryProtocol {
    func fetchMyRoomAccess(roomID: String) async throws -> ChatRoomAccessStatus { .joinable }
    private let notices: [ChatRoomClosureNotice]
    private(set) var fetchCount = 0
    private(set) var acknowledgedRoomIDs: [String] = []

    init(notices: [ChatRoomClosureNotice]) {
        self.notices = notices
    }

    func deleteMessage(
        roomID: String,
        messageID: String,
        expectedSeq: Int64,
        reasonCode: String
    ) async throws -> ChatMessageDeletionReceipt {
        throw ClosureNoticeTestError.unexpectedCall
    }

    func closeOwnedRoom(
        roomID: String,
        expectedLifecycleVersion: Int
    ) async throws -> ChatRoomExitResult {
        throw ClosureNoticeTestError.unexpectedCall
    }

    func fetchClosureNotices() async throws -> [ChatRoomClosureNotice] {
        fetchCount += 1
        return notices
    }

    func acknowledgeClosureNotice(roomID: String) async throws {
        acknowledgedRoomIDs.append(roomID)
    }

    func removeRoomMember(roomID: String, targetUID: String, reasonCode: String) async throws -> ChatRoomMemberRemovalReceipt {
        throw ClosureNoticeTestError.unexpectedCall
    }

    func listRoomBans(roomID: String, pageSize: Int, cursor: String?) async throws -> ChatRoomBanPage {
        throw ClosureNoticeTestError.unexpectedCall
    }

    func unbanRoomMember(roomID: String, banEntryToken: String) async throws {
        throw ClosureNoticeTestError.unexpectedCall
    }
}

private final class EmptyJoinedRoomsUseCaseFake: JoinedRoomsUseCaseProtocol {
    func fetchJoinedRooms(limit: Int?) async throws -> [JoinedRoomListItem] { [] }

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
        throw ClosureNoticeTestError.unexpectedCall
    }
}

private final class StaleJoinedRoomsUseCaseFake: JoinedRoomsUseCaseProtocol {
    private let item: JoinedRoomListItem

    init(room: ChatRoom) {
        self.item = JoinedRoomListItem(
            room: room,
            projection: JoinedRoomProjection(
                documentID: room.id,
                data: [
                    "roomID": room.id,
                    "lastReadSeq": room.seq,
                    "isClosed": room.isClosed
                ]
            )!
        )
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
        throw ClosureNoticeTestError.unexpectedCall
    }
}

@MainActor
private final class DeferredClosureAcknowledgementFake: ChatRoomClosureAcknowledging {
    private var continuation: CheckedContinuation<Void, any Error>?

    var hasPendingRequest: Bool { continuation != nil }

    func acknowledge(roomID: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete() {
        continuation?.resume()
        continuation = nil
    }

    func fail() {
        continuation?.resume(throwing: ClosureNoticeTestError.acknowledgementFailed)
        continuation = nil
    }
}

private enum ClosureNoticeTestError: Error {
    case unexpectedCall
    case acknowledgementFailed
}
