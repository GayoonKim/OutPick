import Foundation
import Testing
@testable import OutPick

@MainActor
struct ChatRoomBannedUsersViewModelTests {
    @Test
    func initialAndNextPageLoadDeduplicatesEntries() async throws {
        let first = ChatRoomBanEntry(
            token: "token-1",
            reasonCode: "spam",
            displayName: "첫 번째",
            bannedAt: nil
        )
        let second = ChatRoomBanEntry(
            token: "token-2",
            reasonCode: "harassment",
            displayName: "두 번째",
            bannedAt: nil
        )
        let useCase = ChatRoomMemberModerationUseCaseFake()
        useCase.pages = [
            ChatRoomBanPage(items: [first], nextCursor: "cursor-2"),
            ChatRoomBanPage(items: [first, second], nextCursor: nil)
        ]
        let viewModel = ChatRoomBannedUsersViewModel(roomID: "room-1", useCase: useCase)

        try await viewModel.loadInitial()
        try await viewModel.loadMore()

        #expect(viewModel.entries.map(\.token) == ["token-1", "token-2"])
        #expect(viewModel.hasMore == false)
        #expect(useCase.loadBanCalls == [
            .init(roomID: "room-1", cursor: nil),
            .init(roomID: "room-1", cursor: "cursor-2")
        ])
    }

    @Test
    func successfulUnbanRemovesOnlySelectedEntry() async throws {
        let first = ChatRoomBanEntry(token: "token-1", reasonCode: "spam", displayName: nil, bannedAt: nil)
        let second = ChatRoomBanEntry(token: "token-2", reasonCode: "other", displayName: nil, bannedAt: nil)
        let useCase = ChatRoomMemberModerationUseCaseFake()
        useCase.pages = [ChatRoomBanPage(items: [first, second], nextCursor: nil)]
        let viewModel = ChatRoomBannedUsersViewModel(roomID: "room-1", useCase: useCase)
        try await viewModel.loadInitial()

        try await viewModel.unban(first)

        #expect(viewModel.entries.map(\.token) == ["token-2"])
        #expect(useCase.unbanCalls == [.init(roomID: "room-1", token: "token-1")])
        #expect(viewModel.isRemoving(first) == false)
    }

    @Test
    func failedUnbanPreservesEntryAndClearsWorkingState() async throws {
        let entry = ChatRoomBanEntry(token: "token-1", reasonCode: "spam", displayName: nil, bannedAt: nil)
        let useCase = ChatRoomMemberModerationUseCaseFake()
        useCase.pages = [ChatRoomBanPage(items: [entry], nextCursor: nil)]
        useCase.unbanError = TestError.expected
        let viewModel = ChatRoomBannedUsersViewModel(roomID: "room-1", useCase: useCase)
        try await viewModel.loadInitial()

        await #expect(throws: TestError.self) {
            try await viewModel.unban(entry)
        }

        #expect(viewModel.entries == [entry])
        #expect(viewModel.isRemoving(entry) == false)
    }
}

private enum TestError: Error {
    case expected
}

private final class ChatRoomMemberModerationUseCaseFake: ChatRoomMemberModerationUseCaseProtocol {
    struct LoadBanCall: Equatable {
        let roomID: String
        let cursor: String?
    }

    struct UnbanCall: Equatable {
        let roomID: String
        let token: String
    }

    var pages: [ChatRoomBanPage] = []
    var unbanError: Error?
    private(set) var loadBanCalls: [LoadBanCall] = []
    private(set) var unbanCalls: [UnbanCall] = []

    func loadMyRoomAccess(roomID: String) async throws -> ChatRoomAccessStatus {
        .joinable
    }

    func removeMember(
        roomID: String,
        targetUID: String,
        reasonCode: String
    ) async throws -> ChatRoomMemberRemovalReceipt {
        ChatRoomMemberRemovalReceipt(memberCount: 0)
    }

    func loadBans(roomID: String, cursor: String?) async throws -> ChatRoomBanPage {
        loadBanCalls.append(.init(roomID: roomID, cursor: cursor))
        return pages.removeFirst()
    }

    func unban(roomID: String, token: String) async throws {
        unbanCalls.append(.init(roomID: roomID, token: token))
        if let unbanError { throw unbanError }
    }
}
