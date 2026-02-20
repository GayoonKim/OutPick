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
    private var hasLoadedInitialRooms = false

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    init(useCase: RoomListUseCaseProtocol) {
        self.useCase = useCase
        self.state = State(rooms: useCase.cachedTopRooms())
    }

    func onAppear() {
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

    func notifyCurrentState() {
        onStateChanged?(state)
    }
}
