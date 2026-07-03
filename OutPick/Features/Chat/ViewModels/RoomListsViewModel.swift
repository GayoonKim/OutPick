//
//  RoomListsViewModel.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

@MainActor
final class RoomListsViewModel {
    struct State: Equatable {
        var rooms: [ChatRoomPreviewItem] = []
        var isRefreshing: Bool = false
        var errorMessage: String?
    }

    private let useCase: RoomListUseCaseProtocol
    private let roomReadStateStore: ChatRoomReadStateStore?
    private var hasLoadedInitialRooms = false
    private var readStateTask: Task<Void, Never>?
    private var isBoundReadState = false

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    init(
        useCase: RoomListUseCaseProtocol,
        roomReadStateStore: ChatRoomReadStateStore? = nil
    ) {
        self.useCase = useCase
        self.roomReadStateStore = roomReadStateStore
        self.state = State(rooms: useCase.cachedTopRooms())
    }

    func onAppear() {
        bindReadStateIfNeeded()
        state.rooms = useCase.cachedTopRooms()
    }

    func loadInitiallyIfNeeded() async {
        guard !hasLoadedInitialRooms else { return }
        hasLoadedInitialRooms = true
        await refreshTopRooms()
    }

    func refreshTopRooms() async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.errorMessage = nil

        do {
            let rooms = try await useCase.refreshTopRooms(limit: 30)
            state.rooms = rooms
        } catch {
            state.errorMessage = "방 목록을 새로고침하지 못했습니다."
        }

        state.isRefreshing = false
    }

    func removeLocalRoom(roomID: String) {
        guard !roomID.isEmpty else { return }
        useCase.removeCachedRoom(roomID: roomID)
        state.rooms.removeAll { $0.room.ID == roomID }
    }

    func notifyCurrentState() {
        onStateChanged?(state)
    }

    private func bindReadStateIfNeeded() {
        guard !isBoundReadState else { return }
        guard let roomReadStateStore else { return }

        isBoundReadState = true
        readStateTask = Task { @MainActor [weak self, weak roomReadStateStore] in
            guard let self, let roomReadStateStore else { return }
            for await _ in roomReadStateStore.readStateChangeStream() {
                if Task.isCancelled { return }
                self.state.rooms = self.useCase.cachedTopRooms()
            }
        }
    }
}
