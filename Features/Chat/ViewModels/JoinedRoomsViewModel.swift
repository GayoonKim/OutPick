//
//  JoinedRoomsViewModel.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation
import Combine

@MainActor
final class JoinedRoomsViewModel {
    struct State: Equatable {
        var rooms: [ChatRoom] = []
        var unreadCounts: [String: Int64] = [:]
        var isLoading: Bool = false
        var errorMessage: String?
    }

    private let useCase: JoinedRoomsUseCaseProtocol
    private var cancellables = Set<AnyCancellable>()
    private var isBoundRoomChanges = false

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    init(useCase: JoinedRoomsUseCaseProtocol) {
        self.useCase = useCase
        self.state = State()
    }

    func start() {
        if !isBoundRoomChanges {
            bindRoomChanges()
        }
        Task { await loadJoinedRooms() }
    }

    func stop() {
        useCase.stopRoomUpdates()
        cancellables.removeAll()
        isBoundRoomChanges = false
    }

    func notifyCurrentState() {
        onStateChanged?(state)
    }

    func leave(room: ChatRoom) {
        useCase.leave(room: room)
    }

    private func bindRoomChanges() {
        useCase.roomChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedRoom in
                guard let self else { return }
                self.applyIncrementalRoomUpdate(updatedRoom)
            }
            .store(in: &cancellables)
        isBoundRoomChanges = true
    }

    private func loadJoinedRooms() async {
        state.isLoading = true
        state.errorMessage = nil

        do {
            let rooms = try await useCase.fetchJoinedRooms()
            let sortedRooms = sortRooms(rooms)
            state.rooms = sortedRooms
            useCase.startRoomUpdates(roomIDs: sortedRooms.compactMap { $0.ID })
            state.unreadCounts = await computeUnreadCounts(for: sortedRooms)
        } catch {
            state.errorMessage = "참여중인 방을 불러오지 못했습니다."
            state.rooms = []
            state.unreadCounts = [:]
        }

        state.isLoading = false
    }

    private func applyIncrementalRoomUpdate(_ updated: ChatRoom) {
        guard let id = updated.ID else { return }
        var rooms = state.rooms
        if let idx = rooms.firstIndex(where: { $0.ID == id }) {
            rooms[idx] = updated
        } else {
            rooms.append(updated)
        }
        state.rooms = sortRooms(rooms)

        Task { [weak self] in
            guard let self else { return }
            let unread = await self.useCase.fetchUnreadCount(roomID: id, lastMessageSeqHint: updated.seq)
            await MainActor.run {
                self.state.unreadCounts[id] = unread
            }
        }
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
