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
        var closureNotices: [ChatRoomClosureNotice] = []
    }

    private let useCase: JoinedRoomsUseCaseProtocol
    private let roomReadStateStore: ChatRoomReadStateStore?
    private let joinedRoomsStore: JoinedRoomsSessionStoring?
    private let moderationLifecycleRepository: ChatModerationLifecycleRepositoryProtocol?
    private let closureAcknowledgementUseCase: ChatRoomClosureAcknowledging?
    private var readStateTask: Task<Void, Never>?
    private var joinedRoomsStoreTask: Task<Void, Never>?
    private var closureNoticeTask: Task<Void, Never>?
    private var closureNoticeGeneration = 0
    private var acknowledgedClosureNoticeIDs: Set<String> = []
    private var locallyConfirmedClosureRoomIDs: Set<String> = []
    private var isBoundReadState = false
    private var isBoundJoinedRoomsStore = false
    private var joinedItems: [JoinedRoomListItem] = []

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    init(
        useCase: JoinedRoomsUseCaseProtocol,
        roomReadStateStore: ChatRoomReadStateStore? = nil,
        joinedRoomsStore: JoinedRoomsSessionStoring? = nil,
        moderationLifecycleRepository: ChatModerationLifecycleRepositoryProtocol? = nil,
        closureAcknowledgementUseCase: ChatRoomClosureAcknowledging? = nil
    ) {
        self.useCase = useCase
        self.roomReadStateStore = roomReadStateStore
        self.joinedRoomsStore = joinedRoomsStore
        self.moderationLifecycleRepository = moderationLifecycleRepository
        self.closureAcknowledgementUseCase = closureAcknowledgementUseCase
        self.state = State()
    }

    func start() {
        bindReadStateIfNeeded()
        bindJoinedRoomsStoreIfNeeded()
        pruneRoomsNotInSessionStore(joinedRoomsStore?.joined ?? [])
        Task { await reloadJoinedRooms() }
        closureNoticeGeneration += 1
        let generation = closureNoticeGeneration
        closureNoticeTask?.cancel()
        closureNoticeTask = Task { @MainActor [weak self] in
            await self?.loadClosureNotices(generation: generation)
        }
    }

    func stop() {
        readStateTask?.cancel()
        readStateTask = nil
        joinedRoomsStoreTask?.cancel()
        joinedRoomsStoreTask = nil
        closureNoticeGeneration += 1
        closureNoticeTask?.cancel()
        closureNoticeTask = nil
        isBoundReadState = false
        isBoundJoinedRoomsStore = false
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
        guard let target = state.rooms.first(where: { $0.id == roomID }) else { return }
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

    func acknowledgeClosureNotice(_ notice: ChatRoomClosureNotice) async throws {
        if let closureAcknowledgementUseCase {
            try await closureAcknowledgementUseCase.acknowledge(roomID: notice.roomID)
        } else if let moderationLifecycleRepository {
            try await moderationLifecycleRepository.acknowledgeClosureNotice(roomID: notice.roomID)
        }
        acknowledgedClosureNoticeIDs.insert(notice.roomID)
        state.closureNotices.removeAll { $0.roomID == notice.roomID }
    }

    func acknowledgeClosedRoom(_ room: ChatRoom) async throws {
        guard room.isClosed else { return }
        let removedItems = joinedItems.filter { $0.roomID == room.id }
        let removedUnreadCount = state.unreadCounts[room.id]
        let removedNotices = state.closureNotices.filter { $0.roomID == room.id }
        hideClosedRoom(roomID: room.id)

        do {
            if let closureAcknowledgementUseCase {
                try await closureAcknowledgementUseCase.acknowledge(roomID: room.id)
            } else if let moderationLifecycleRepository {
                try await moderationLifecycleRepository.acknowledgeClosureNotice(roomID: room.id)
            }
        } catch {
            locallyConfirmedClosureRoomIDs.remove(room.id)
            joinedItems = sortItems(joinedItems + removedItems)
            state.rooms = joinedItems.map(\.room)
            if let removedUnreadCount {
                state.unreadCounts[room.id] = removedUnreadCount
            }
            state.closureNotices.append(contentsOf: removedNotices)
            throw error
        }
    }

    func removeRoomAfterRealtimeClosure(roomID: String) {
        guard !roomID.isEmpty else { return }
        hideClosedRoom(roomID: roomID)
    }

    private func hideClosedRoom(roomID: String) {
        locallyConfirmedClosureRoomIDs.insert(roomID)
        joinedItems.removeAll { $0.roomID == roomID }
        state.rooms.removeAll { $0.id == roomID }
        state.unreadCounts.removeValue(forKey: roomID)
        state.closureNotices.removeAll { $0.roomID == roomID }
    }

    private func loadClosureNotices(generation: Int) async {
        guard let moderationLifecycleRepository else { return }
        do {
            let notices = try await moderationLifecycleRepository.fetchClosureNotices()
            guard !Task.isCancelled, generation == closureNoticeGeneration else { return }
            state.closureNotices = notices.filter {
                !acknowledgedClosureNoticeIDs.contains($0.roomID) &&
                    !locallyConfirmedClosureRoomIDs.contains($0.roomID)
            }
        } catch {
            // 참여방 목록은 안내 projection 조회 실패와 독립적으로 계속 표시한다.
        }
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

    private func bindJoinedRoomsStoreIfNeeded() {
        guard !isBoundJoinedRoomsStore else { return }
        guard let joinedRoomsStore else { return }

        isBoundJoinedRoomsStore = true
        joinedRoomsStoreTask = Task { @MainActor [weak self, weak joinedRoomsStore] in
            guard let self, let joinedRoomsStore else { return }
            for await joinedRoomIDs in joinedRoomsStore.changeStream() {
                if Task.isCancelled { return }
                self.pruneRoomsNotInSessionStore(joinedRoomIDs)
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
            let roomID = room.id
            return (roomID, (room.seq, room.lastMessageAt, room.lastMessage, room.lastMessageSenderUID))
        })

        joinedItems = sortItems(items.filter { !locallyConfirmedClosureRoomIDs.contains($0.roomID) })
        seedReadState(from: joinedItems)
        state.rooms = joinedItems.map(\.room)

        guard updateUnread else { return }
        let changedRooms = joinedItems.map(\.room).filter { room in
            guard !room.isClosed else { return false }
            let roomID = room.id
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
            let resolvedSnapshot = roomReadStateStore?.seed(snapshot) ?? snapshot
            if let unread = resolvedSnapshot.unreadCount(currentUserID: currentUserID) {
                updates[resolvedSnapshot.roomID] = unread
            }
        }
        state.unreadCounts.merge(updates) { _, new in new }
    }

    private func computeUnreadCounts(from items: [JoinedRoomListItem]) -> [String: Int64] {
        let currentUserID = LoginManager.shared.canonicalUserID
        var result: [String: Int64] = [:]
        for item in items {
            guard !item.room.isClosed else { continue }
            let snapshot = item.readSnapshot()
            let resolvedSnapshot = roomReadStateStore?.seed(snapshot) ?? snapshot
            if let unread = resolvedSnapshot.unreadCount(currentUserID: currentUserID) {
                result[resolvedSnapshot.roomID] = unread
            }
        }
        return result
    }

    private func fetchReadSnapshots(for rooms: [ChatRoom]) async -> [ChatRoomReadSnapshot] {
        let currentUserID = LoginManager.shared.canonicalUserID
        return await withTaskGroup(of: ChatRoomReadSnapshot?.self, returning: [ChatRoomReadSnapshot].self) { group in
            for room in rooms where !room.isClosed {
                let roomID = room.id
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
        for item in items where !item.room.isClosed {
            roomReadStateStore.seed(item.readSnapshot())
        }
    }

    private func applyReadStateChange(_ change: ChatRoomReadStateChange) {
        guard state.rooms.contains(where: { $0.id == change.roomID }) else { return }
        guard let unread = change.snapshot.unreadCount(currentUserID: LoginManager.shared.canonicalUserID) else { return }
        state.unreadCounts[change.roomID] = unread
        applyRoomSummaryChange(change)
    }

    private func applyRoomSummaryChange(_ change: ChatRoomReadStateChange) {
        guard change.snapshot.latestSeq != nil ||
            change.snapshot.latestMessagePreview != nil ||
            change.snapshot.latestMessageAt != nil ||
            change.snapshot.lastMessageSenderUID != nil else {
            return
        }

        func update(_ room: inout ChatRoom) {
            if let latestSeq = change.snapshot.latestSeq, latestSeq > room.seq {
                room.seq = latestSeq
            }
            if let preview = change.snapshot.latestMessagePreview {
                room.lastMessage = preview
            }
            if let date = change.snapshot.latestMessageAt {
                room.lastMessageAt = date
            }
            if let senderUID = change.snapshot.lastMessageSenderUID {
                room.lastMessageSenderUID = senderUID
            }
        }

        var didUpdate = false
        state.rooms = state.rooms.map { room in
            guard room.id == change.roomID else { return room }
            var copy = room
            update(&copy)
            didUpdate = true
            return copy
        }

        if didUpdate {
            joinedItems = joinedItems.map { item in
                guard item.room.id == change.roomID else { return item }
                var room = item.room
                update(&room)
                return JoinedRoomListItem(room: room, projection: item.projection)
            }
            joinedItems = sortItems(joinedItems)
            state.rooms = sortItems(joinedItems).map(\.room)
        }
    }

    private func pruneRoomsNotInSessionStore(_ joinedRoomIDs: Set<String>) {
        guard !joinedRoomIDs.isEmpty || !state.rooms.isEmpty else { return }
        let removedRoomIDs = Set(state.rooms.filter { !$0.isClosed }.map(\.id))
            .subtracting(joinedRoomIDs)
        guard !removedRoomIDs.isEmpty else { return }

        joinedItems.removeAll { item in
            removedRoomIDs.contains(item.room.id)
        }
        state.rooms.removeAll { room in
            removedRoomIDs.contains(room.id)
        }
        for roomID in removedRoomIDs {
            state.unreadCounts.removeValue(forKey: roomID)
        }
    }

    private func sortItems(_ items: [JoinedRoomListItem]) -> [JoinedRoomListItem] {
        items.sorted { lhs, rhs in
            (lhs.room.lastMessageAt ?? lhs.room.createdAt) > (rhs.room.lastMessageAt ?? rhs.room.createdAt)
        }
    }

}
