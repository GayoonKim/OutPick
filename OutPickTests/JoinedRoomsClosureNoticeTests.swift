import Foundation
import Testing
@testable import OutPick

@MainActor
struct JoinedRoomsClosureNoticeTests {
    @Test func noticeUsesRoomNameAndFriendlyWording() {
        let ownerNotice = notice(type: .closedByOwner)
        let moderationNotice = notice(type: .closedByModeration)

        #expect(ownerNotice.title == "“QA 채팅방” 채팅방이 종료됐어요")
        #expect(ownerNotice.message == "방장이 채팅방을 삭제했어요.")
        #expect(moderationNotice.message == "운영 정책에 따라 채팅방 이용이 종료됐어요.")
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

private enum ClosureNoticeTestError: Error {
    case unexpectedCall
}
