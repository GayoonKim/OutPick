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
    private var cancellables = Set<AnyCancellable>()
    private var isBoundJoinedRooms = false
    private var headRooms: [ChatRoom] = []
    private var tailRoomsByID: [String: ChatRoom] = [:]
    private var tailCursor: DocumentSnapshot?
    private var hasMoreTailPages: Bool = true
    private var lastTailSyncAt: Date?

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    init(useCase: JoinedRoomsUseCaseProtocol) {
        self.useCase = useCase
        self.state = State()
    }

    func start() {
        if !isBoundJoinedRooms {
            bindJoinedRoomsSummary()
        }
        useCase.startRoomUpdates(limit: Constants.headRealtimeLimit)
        Task { await bootstrapJoinedRooms() }
    }

    func stop() {
        useCase.stopRoomUpdates()
        cancellables.removeAll()
        isBoundJoinedRooms = false
    }

    func notifyCurrentState() {
        onStateChanged?(state)
    }

    func leave(room: ChatRoom) {
        useCase.leave(room: room)
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

    private func bootstrapJoinedRooms() async {
        state.isLoading = true
        state.errorMessage = nil
        let previousTailSyncAt = lastTailSyncAt

        do {
            let headResult = try await useCase.fetchJoinedRoomsHead(limit: Constants.headRealtimeLimit)
            tailCursor = headResult.cursor
            hasMoreTailPages = headResult.rooms.count >= Constants.headRealtimeLimit
            applyHeadRooms(headResult.rooms, updateUnread: false)

            if let previousTailSyncAt {
                try await syncTailChanges(since: previousTailSyncAt)
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
        let previousSeqByID = Dictionary(uniqueKeysWithValues: headRooms.compactMap { room -> (String, Int64)? in
            guard let roomID = room.ID else { return nil }
            return (roomID, room.seq)
        })

        headRooms = sortRooms(rooms)
        rebuildMergedState()

        guard updateUnread else { return }
        let changedRooms = headRooms.filter { room in
            guard let roomID = room.ID else { return false }
            guard let oldSeq = previousSeqByID[roomID] else { return true }
            return oldSeq != room.seq
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
        let updates = await withTaskGroup(of: (String, Int64)?.self, returning: [String: Int64].self) { group in
            for room in rooms {
                guard let roomID = room.ID else { continue }
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    let unread = await self.useCase.fetchUnreadCount(
                        roomID: roomID,
                        lastMessageSeqHint: room.seq
                    )
                    return (roomID, unread)
                }
            }

            var result: [String: Int64] = [:]
            for await item in group {
                if let (roomID, unread) = item {
                    result[roomID] = unread
                }
            }
            return result
        }
        state.unreadCounts.merge(updates) { _, new in new }
    }

    private func computeUnreadCounts(for rooms: [ChatRoom]) async -> [String: Int64] {
        await withTaskGroup(of: (String, Int64)?.self, returning: [String: Int64].self) { group in
            for room in rooms {
                guard let roomID = room.ID else { continue }
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    let unread = await self.useCase.fetchUnreadCount(roomID: roomID, lastMessageSeqHint: room.seq)
                    return (roomID, unread)
                }
            }

            var result: [String: Int64] = [:]
            for await item in group {
                if let (roomID, unread) = item {
                    result[roomID] = unread
                }
            }
            return result
        }
    }

    private func sortRooms(_ rooms: [ChatRoom]) -> [ChatRoom] {
        rooms.sorted { lhs, rhs in
            (lhs.lastMessageAt ?? lhs.createdAt) > (rhs.lastMessageAt ?? rhs.createdAt)
        }
    }
}
