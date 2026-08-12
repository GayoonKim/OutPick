import Foundation

@MainActor
final class ChatRoomBannedUsersViewModel {
    private(set) var entries: [ChatRoomBanEntry] = []
    private(set) var isInitialLoading = false
    private(set) var isLoadingMore = false
    private(set) var removingTokens = Set<String>()
    private(set) var nextCursor: String?

    private let roomID: String
    private let useCase: ChatRoomMemberModerationUseCaseProtocol

    init(roomID: String, useCase: ChatRoomMemberModerationUseCaseProtocol) {
        self.roomID = roomID
        self.useCase = useCase
    }

    var hasMore: Bool { nextCursor != nil }

    func loadInitial() async throws {
        guard !isInitialLoading else { return }
        isInitialLoading = true
        defer { isInitialLoading = false }

        let page = try await useCase.loadBans(roomID: roomID, cursor: nil)
        entries = Self.uniqued(page.items)
        nextCursor = page.nextCursor
    }

    func loadMore() async throws {
        guard let cursor = nextCursor, !isLoadingMore, !isInitialLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let page = try await useCase.loadBans(roomID: roomID, cursor: cursor)
        entries = Self.uniqued(entries + page.items)
        nextCursor = page.nextCursor
    }

    func unban(_ entry: ChatRoomBanEntry) async throws {
        guard removingTokens.insert(entry.token).inserted else { return }
        defer { removingTokens.remove(entry.token) }

        try await useCase.unban(roomID: roomID, token: entry.token)
        entries.removeAll { $0.token == entry.token }
    }

    func isRemoving(_ entry: ChatRoomBanEntry) -> Bool {
        removingTokens.contains(entry.token)
    }

    private static func uniqued(_ entries: [ChatRoomBanEntry]) -> [ChatRoomBanEntry] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.token).inserted }
    }
}
