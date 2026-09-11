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
    private var profileRefreshTask: Task<Void, Never>?
    private var isBoundReadState = false
    private var requestGeneration = 0

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
        self.state = State()
    }

    func onAppear() {
        bindReadStateIfNeeded()
        // 복귀 첫 프레임에도 삭제 전 미리보기를 재사용하지 않는다.
        state.rooms = state.rooms.map { ChatRoomPreviewItem(room: $0.room, messages: []) }
        reloadCachedRooms()
    }

    private func reloadCachedRooms() {
        requestGeneration += 1
        let generation = requestGeneration
        profileRefreshTask?.cancel()
        profileRefreshTask = Task { [weak self] in
            guard let self else { return }
            let cached = await self.useCase.cachedTopRooms()
            guard Task.isCancelled == false, self.requestGeneration == generation else { return }
            self.state.rooms = cached
            let rooms = await self.useCase.refreshCachedProfiles()
            guard Task.isCancelled == false, self.requestGeneration == generation else { return }
            self.state.rooms = rooms
        }
    }

    func loadInitiallyIfNeeded() async {
        guard !hasLoadedInitialRooms else { return }
        hasLoadedInitialRooms = true
        await refreshTopRooms()
    }

    func refreshTopRooms() async {
        guard !state.isRefreshing else { return }
        requestGeneration += 1
        let generation = requestGeneration
        profileRefreshTask?.cancel()
        state.isRefreshing = true
        state.errorMessage = nil

        do {
            let rooms = try await useCase.refreshTopRooms(limit: 30)
            if requestGeneration == generation { state.rooms = rooms }
        } catch {
            state.errorMessage = "방 목록을 새로고침하지 못했습니다."
        }

        state.isRefreshing = false
    }

    func removeLocalRoom(roomID: String) {
        guard !roomID.isEmpty else { return }
        requestGeneration += 1
        profileRefreshTask?.cancel()
        useCase.removeCachedRoom(roomID: roomID)
        state.rooms.removeAll { $0.room.id == roomID }
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
                self.reloadCachedRooms()
            }
        }
    }
}
