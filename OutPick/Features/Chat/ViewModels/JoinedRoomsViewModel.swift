//
//  JoinedRoomsViewModel.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

@MainActor
final class JoinedRoomsViewModel {
    struct State: Equatable {
        var rooms: [ChatRoom] = []
        var unreadCounts: [String: Int64] = [:]
        var isLoading: Bool = false
        var errorMessage: String?
    }

    private let useCase: JoinedRoomsUseCaseProtocol
    private let roomReadStateStore: ChatRoomReadStateStore?
    private var readStateTask: Task<Void, Never>?
    private var isBoundReadState = false
    private var joinedItems: [JoinedRoomListItem] = []

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    init(
        useCase: JoinedRoomsUseCaseProtocol,
        roomReadStateStore: ChatRoomReadStateStore? = nil
    ) {
        self.useCase = useCase
        self.roomReadStateStore = roomReadStateStore
        self.state = State()
    }

    func start() {
        bindReadStateIfNeeded()
        Task { await reloadJoinedRooms() }
    }

    func stop() {
        readStateTask?.cancel()
        readStateTask = nil
        isBoundReadState = false
    }

    func notifyCurrentState() {
        onStateChanged?(state)
    }

    func canLeaveFromList(room: ChatRoom) -> Bool {
        useCase.canLeaveFromList(room: room)
    }

    func leave(room: ChatRoom) async throws -> ChatRoomExitResult {
        try await useCase.leave(room: room)
    }

    func refreshUnreadCount(roomID: String) {
        guard let target = state.rooms.first(where: { $0.ID == roomID }) else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshUnreadCounts(for: [target])
        }
    }

    func loadMoreJoinedRooms() async {
        // joinedRooms projection은 사용자당 참여 방 수가 제한적이라는 전제로 전체 fetch 후 클라이언트 정렬한다.
    }

    func reloadJoinedRooms() async {
        await bootstrapJoinedRooms()
    }

    private func bindReadStateIfNeeded() {
        guard !isBoundReadState else { return }
        guard let roomReadStateStore else { return }

        isBoundReadState = true
        readStateTask = Task { @MainActor [weak self, weak roomReadStateStore] in
            guard let self, let roomReadStateStore else { return }
            for await change in roomReadStateStore.readStateChangeStream() {
                if Task.isCancelled { return }
                self.applyReadStateChange(change)
            }
        }
    }

    private func bootstrapJoinedRooms() async {
        state.isLoading = true
        state.errorMessage = nil

        do {
            let items = try await useCase.fetchJoinedRooms(limit: nil)
            applyJoinedItems(items, updateUnread: false)

            state.unreadCounts = computeUnreadCounts(from: joinedItems)
        } catch {
            state.errorMessage = "참여중인 방을 불러오지 못했습니다."
            state.rooms = []
            state.unreadCounts = [:]
            joinedItems = []
        }

        state.isLoading = false
    }

    private func applyJoinedItems(_ items: [JoinedRoomListItem], updateUnread: Bool = true) {
        let previousSummaryByID = Dictionary(uniqueKeysWithValues: joinedItems.compactMap { item -> (String, (seq: Int64, lastMessageAt: Date?, lastMessage: String?, lastMessageSenderUID: String?))? in
            let room = item.room
            guard let roomID = room.ID else { return nil }
            return (roomID, (room.seq, room.lastMessageAt, room.lastMessage, room.lastMessageSenderUID))
        })

        joinedItems = sortItems(items)
        seedReadState(from: joinedItems)
        state.rooms = joinedItems.map(\.room)

        guard updateUnread else { return }
        let changedRooms = joinedItems.map(\.room).filter { room in
            guard let roomID = room.ID else { return false }
            guard let old = previousSummaryByID[roomID] else { return true }
            return old.seq != room.seq ||
                old.lastMessageAt != room.lastMessageAt ||
                old.lastMessage != room.lastMessage ||
                old.lastMessageSenderUID != room.lastMessageSenderUID
        }
        guard !changedRooms.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshUnreadCounts(for: changedRooms)
        }
    }

    private func refreshUnreadCounts(for rooms: [ChatRoom]) async {
        let snapshots = await fetchReadSnapshots(for: rooms)
        var updates: [String: Int64] = [:]
        let currentUserID = LoginManager.shared.canonicalUserID
        for snapshot in snapshots {
            roomReadStateStore?.seed(snapshot)
            if let unread = snapshot.unreadCount(currentUserID: currentUserID) {
                updates[snapshot.roomID] = unread
            }
        }
        state.unreadCounts.merge(updates) { _, new in new }
    }

    private func computeUnreadCounts(from items: [JoinedRoomListItem]) -> [String: Int64] {
        let currentUserID = LoginManager.shared.canonicalUserID
        var result: [String: Int64] = [:]
        for item in items {
            let snapshot = item.readSnapshot()
            roomReadStateStore?.seed(snapshot)
            if let unread = snapshot.unreadCount(currentUserID: currentUserID) {
                result[snapshot.roomID] = unread
            }
        }
        return result
    }

    private func fetchReadSnapshots(for rooms: [ChatRoom]) async -> [ChatRoomReadSnapshot] {
        let currentUserID = LoginManager.shared.canonicalUserID
        return await withTaskGroup(of: ChatRoomReadSnapshot?.self, returning: [ChatRoomReadSnapshot].self) { group in
            for room in rooms {
                guard let roomID = room.ID else { continue }
                if let snapshot = roomReadStateStore?.snapshot(for: roomID),
                   snapshot.unreadCount(currentUserID: currentUserID) != nil {
                    group.addTask {
                        snapshot
                    }
                    continue
                }

                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.useCase.fetchReadSnapshot(
                        roomID: roomID,
                        lastMessageSeqHint: room.seq,
                        lastMessageSenderUID: room.lastMessageSenderUID
                    )
                }
            }

            var result: [ChatRoomReadSnapshot] = []
            for await item in group {
                if let item {
                    result.append(item)
                }
            }
            return result
        }
    }

    private func seedReadState(from items: [JoinedRoomListItem]) {
        guard let roomReadStateStore else { return }
        for item in items {
            roomReadStateStore.seed(item.readSnapshot())
        }
    }

    private func applyReadStateChange(_ change: ChatRoomReadStateChange) {
        guard state.rooms.contains(where: { $0.ID == change.roomID }) else { return }
        guard let unread = change.snapshot.unreadCount(currentUserID: LoginManager.shared.canonicalUserID) else { return }
        state.unreadCounts[change.roomID] = unread
    }

    private func sortItems(_ items: [JoinedRoomListItem]) -> [JoinedRoomListItem] {
        items.sorted { lhs, rhs in
            (lhs.room.lastMessageAt ?? lhs.room.createdAt) > (rhs.room.lastMessageAt ?? rhs.room.createdAt)
        }
    }

}
