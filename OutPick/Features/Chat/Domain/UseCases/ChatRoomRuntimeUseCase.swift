//
//  ChatRoomRuntimeUseCase.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

@MainActor
protocol ChatRoomRuntimeUseCaseProtocol {
    func observeRoomClosed(roomID: String, onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription
    func enterVisibleRoom(roomID: String) async
    func leaveVisibleRoom() async
    func cleanTransientLocalRoomData(roomID: String) async
}

@MainActor
final class ChatRoomRuntimeUseCase: ChatRoomRuntimeUseCaseProtocol {
    private let repository: ChatRoomRuntimeRepositoryProtocol
    private let visibilityRuntimeManager: ChatRoomVisibilityRuntimeManaging
    private let transientLocalDataCleaner: ChatRoomTransientLocalDataCleaning

    init(
        repository: ChatRoomRuntimeRepositoryProtocol,
        visibilityRuntimeManager: ChatRoomVisibilityRuntimeManaging,
        transientLocalDataCleaner: ChatRoomTransientLocalDataCleaning
    ) {
        self.repository = repository
        self.visibilityRuntimeManager = visibilityRuntimeManager
        self.transientLocalDataCleaner = transientLocalDataCleaner
    }

    func observeRoomClosed(roomID: String, onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription {
        repository.observeRoomClosed(roomID: roomID, onClosed: onClosed)
    }

    func enterVisibleRoom(roomID: String) async {
        await visibilityRuntimeManager.enterVisibleRoom(roomID: roomID)
    }

    func leaveVisibleRoom() async {
        await visibilityRuntimeManager.leaveVisibleRoom()
    }

    func cleanTransientLocalRoomData(roomID: String) async {
        do {
            try await transientLocalDataCleaner.cleanTransientLocalRoomData(roomID: roomID)
        } catch {
            print("❌ transient local room cleanup failed:", error)
        }
    }
}
