//
//  JoinedRoomsViewModel.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class JoinedRoomsViewModel {
    private enum Constants {
        static let headRealtimeLimit: Int = 50
        static let tailPageSize: Int = 50
        static let tailSyncLimit: Int = 200
    }

    struct State: Equatable {
        var rooms: [ChatRoom] = []
        var unreadCounts: [String: Int64] = [:]
        var isLoading: Bool = false
        var errorMessage: String?
    }

    private let useCase: JoinedRoomsUseCaseProtocol
    private let roomReadStateStore: ChatRoomReadStateStore?
    private var cancellables = Set<AnyCancellable>()
    private var readStateTask: Task<Void, Never>?
    private var isBoundJoinedRooms = false
    private var isBoundReadState = false
    private var headRooms: [ChatRoom] = []
    private var tailRoomsByID: [String: ChatRoom] = [:]
    private var tailCursor: DocumentSnapshot?
    private var hasMoreTailPages: Bool = true
    private var lastTailSyncAt: Date?
    private var isTailSyncEnabled: Bool = true
    private var hasLoggedTailSyncIndexIssue: Bool = false

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
        if !isBoundJoinedRooms {
            bindJoinedRoomsSummary()
        }
        bindReadStateIfNeeded()
        useCase.startRoomUpdates(limit: Constants.headRealtimeLimit)
        Task { await bootstrapJoinedRooms() }
    }

    func stop() {
        useCase.stopRoomUpdates()
        cancellables.removeAll()
        readStateTask?.cancel()
        readStateTask = nil
        isBoundJoinedRooms = false
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
        guard hasMoreTailPages else { return }
        do {
            let result = try await useCase.loadMoreJoinedRooms(
                after: tailCursor,
                limit: Constants.tailPageSize
            )
            tailCursor = result.cursor
            hasMoreTailPages = result.rooms.count >= Constants.tailPageSize
            applyTailRooms(result.rooms)
            await refreshUnreadCounts(for: result.rooms)
        } catch {
            state.errorMessage = "추가 참여 방을 불러오지 못했습니다."
        }
    }

    private func bindJoinedRoomsSummary() {
        useCase.joinedRoomsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rooms in
                guard let self else { return }
                self.applyHeadRooms(rooms)
            }
            .store(in: &cancellables)
        isBoundJoinedRooms = true
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
        let previousTailSyncAt = lastTailSyncAt

        do {
            let headResult = try await useCase.fetchJoinedRoomsHead(limit: Constants.headRealtimeLimit)
            tailCursor = headResult.cursor
            hasMoreTailPages = headResult.rooms.count >= Constants.headRealtimeLimit
            applyHeadRooms(headResult.rooms, updateUnread: false)

            if let previousTailSyncAt, isTailSyncEnabled {
                do {
                    try await syncTailChanges(since: previousTailSyncAt)
                } catch {
                    if isMissingFirestoreIndexError(error) {
                        isTailSyncEnabled = false
                        if !hasLoggedTailSyncIndexIssue {
                            hasLoggedTailSyncIndexIssue = true
                            print("⚠️ JoinedRooms tail sync skipped: missing Firestore composite index(updatedAt).")
                        }
                    } else {
                        throw error
                    }
                }
            }

            state.unreadCounts = await computeUnreadCounts(for: state.rooms)
            lastTailSyncAt = Date()
        } catch {
            state.errorMessage = "참여중인 방을 불러오지 못했습니다."
            state.rooms = []
            state.unreadCounts = [:]
        }

        state.isLoading = false
    }

    private func syncTailChanges(since: Date) async throws {
        let changedRooms = try await useCase.syncJoinedRoomsTail(
            since: since,
            limit: Constants.tailSyncLimit
        )
        guard !changedRooms.isEmpty else { return }
        applyTailRooms(changedRooms)
        await refreshUnreadCounts(for: changedRooms)
    }

    private func applyHeadRooms(_ rooms: [ChatRoom], updateUnread: Bool = true) {
        let previousSummaryByID = Dictionary(uniqueKeysWithValues: headRooms.compactMap { room -> (String, (seq: Int64, lastMessageAt: Date?, lastMessage: String?, lastMessageSenderUID: String?))? in
            guard let roomID = room.ID else { return nil }
            return (roomID, (room.seq, room.lastMessageAt, room.lastMessage, room.lastMessageSenderUID))
        })

        headRooms = sortRooms(rooms)
        seedLatestReadState(for: headRooms)
        rebuildMergedState()

        guard updateUnread else { return }
        let changedRooms = headRooms.filter { room in
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

    private func applyTailRooms(_ rooms: [ChatRoom]) {
        for room in rooms {
            guard let roomID = room.ID else { continue }
            tailRoomsByID[roomID] = room
        }
        seedLatestReadState(for: rooms)
        rebuildMergedState()
    }

    private func rebuildMergedState() {
        let headIDs = Set(headRooms.compactMap(\.ID))
        let tailRooms = tailRoomsByID.values.filter { room in
            guard let roomID = room.ID else { return false }
            return !headIDs.contains(roomID)
        }
        let merged = sortRooms(headRooms + tailRooms)
        state.rooms = merged

        let validIDs = Set(merged.compactMap(\.ID))
        state.unreadCounts = state.unreadCounts.filter { validIDs.contains($0.key) }
    }

    private func refreshUnreadCounts(for rooms: [ChatRoom]) async {
        let snapshots = await fetchReadSnapshots(for: rooms)
        var updates: [String: Int64] = [:]
        let currentUserID = LoginManager.shared.getUserUID
        for snapshot in snapshots {
            roomReadStateStore?.seed(snapshot)
            if let unread = snapshot.unreadCount(currentUserID: currentUserID) {
                updates[snapshot.roomID] = unread
            }
        }
        state.unreadCounts.merge(updates) { _, new in new }
    }

    private func computeUnreadCounts(for rooms: [ChatRoom]) async -> [String: Int64] {
        let snapshots = await fetchReadSnapshots(for: rooms)
        let currentUserID = LoginManager.shared.getUserUID
        var result: [String: Int64] = [:]
        for snapshot in snapshots {
            roomReadStateStore?.seed(snapshot)
            if let unread = snapshot.unreadCount(currentUserID: currentUserID) {
                result[snapshot.roomID] = unread
            }
        }
        return result
    }

    private func fetchReadSnapshots(for rooms: [ChatRoom]) async -> [ChatRoomReadSnapshot] {
        let currentUserID = LoginManager.shared.getUserUID
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

    private func seedLatestReadState(for rooms: [ChatRoom]) {
        guard let roomReadStateStore else { return }
        for room in rooms {
            guard let roomID = room.ID else { continue }
            roomReadStateStore.seedLatest(
                roomID: roomID,
                latestSeq: room.seq,
                lastMessageSenderUID: room.lastMessageSenderUID
            )
        }
    }

    private func applyReadStateChange(_ change: ChatRoomReadStateChange) {
        guard state.rooms.contains(where: { $0.ID == change.roomID }) else { return }
        guard let unread = change.snapshot.unreadCount(currentUserID: LoginManager.shared.getUserUID) else { return }
        state.unreadCounts[change.roomID] = unread
    }

    private func sortRooms(_ rooms: [ChatRoom]) -> [ChatRoom] {
        rooms.sorted { lhs, rhs in
            (lhs.lastMessageAt ?? lhs.createdAt) > (rhs.lastMessageAt ?? rhs.createdAt)
        }
    }

    private func isMissingFirestoreIndexError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "FIRFirestoreErrorDomain", nsError.code == 9 else { return false }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("requires an index")
    }
}
