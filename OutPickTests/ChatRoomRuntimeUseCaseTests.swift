//
//  ChatRoomRuntimeUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 6/18/26.
//

import Foundation
import Testing
@testable import OutPick

@MainActor
struct ChatRoomRuntimeUseCaseTests {
    @Test func observeRoomClosedDelegatesToRepository() {
        let repository = ChatRoomRuntimeRepositorySpy()
        let cleaner = ChatRoomTransientLocalDataCleanerSpy()
        let useCase = ChatRoomRuntimeUseCase(
            repository: repository,
            visibilityRuntimeManager: ChatRoomVisibilityRuntimeManagerSpy(),
            transientLocalDataCleaner: cleaner
        )
        var closedRoomIDs: [String] = []

        _ = useCase.observeRoomClosed(roomID: "room-1") { roomID in
            closedRoomIDs.append(roomID)
        }
        repository.emitClosed(roomID: "room-1")

        #expect(repository.observedRoomIDs == ["room-1"])
        #expect(closedRoomIDs == ["room-1"])
    }

    @Test func runtimeSubscriptionStopsOnlyOnce() {
        var stopCount = 0
        let subscription = ChatRoomRuntimeSubscription {
            stopCount += 1
        }

        subscription.stop()
        subscription.stop()

        #expect(stopCount == 1)
    }

    @Test func cleanTransientLocalRoomDataDelegatesToCleaner() async {
        let repository = ChatRoomRuntimeRepositorySpy()
        let cleaner = ChatRoomTransientLocalDataCleanerSpy()
        let useCase = ChatRoomRuntimeUseCase(
            repository: repository,
            visibilityRuntimeManager: ChatRoomVisibilityRuntimeManagerSpy(),
            transientLocalDataCleaner: cleaner
        )

        await useCase.cleanTransientLocalRoomData(roomID: "room-1")

        #expect(cleaner.cleanedRoomIDs == ["room-1"])
    }

    @Test func cleanTransientLocalRoomDataSwallowsCleanerFailure() async {
        let repository = ChatRoomRuntimeRepositorySpy()
        let cleaner = ChatRoomTransientLocalDataCleanerSpy(error: RuntimeTestError.cleanup)
        let useCase = ChatRoomRuntimeUseCase(
            repository: repository,
            visibilityRuntimeManager: ChatRoomVisibilityRuntimeManagerSpy(),
            transientLocalDataCleaner: cleaner
        )

        await useCase.cleanTransientLocalRoomData(roomID: "room-1")

        #expect(cleaner.cleanedRoomIDs == ["room-1"])
    }

    @Test func visibleRoomLifecycleDelegatesToRuntimeManager() async {
        let repository = ChatRoomRuntimeRepositorySpy()
        let visibilityRuntimeManager = ChatRoomVisibilityRuntimeManagerSpy()
        let cleaner = ChatRoomTransientLocalDataCleanerSpy()
        let useCase = ChatRoomRuntimeUseCase(
            repository: repository,
            visibilityRuntimeManager: visibilityRuntimeManager,
            transientLocalDataCleaner: cleaner
        )

        await useCase.enterVisibleRoom(roomID: "room-1")
        await useCase.leaveVisibleRoom()

        #expect(visibilityRuntimeManager.enteredRoomIDs == ["room-1"])
        #expect(visibilityRuntimeManager.leaveCallCount == 1)
    }
}

@MainActor
private final class ChatRoomRuntimeRepositorySpy: ChatRoomRuntimeRepositoryProtocol {
    private var onClosed: ((String) -> Void)?
    private(set) var observedRoomIDs: [String] = []

    func observeRoomClosed(roomID: String, onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription {
        observedRoomIDs.append(roomID)
        self.onClosed = onClosed
        return ChatRoomRuntimeSubscription()
    }

    func emitClosed(roomID: String) {
        onClosed?(roomID)
    }
}

private final class ChatRoomTransientLocalDataCleanerSpy: ChatRoomTransientLocalDataCleaning {
    private let error: Error?
    private(set) var cleanedRoomIDs: [String] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func cleanTransientLocalRoomData(roomID: String) async throws {
        cleanedRoomIDs.append(roomID)
        if let error {
            throw error
        }
    }
}

@MainActor
private final class ChatRoomVisibilityRuntimeManagerSpy: ChatRoomVisibilityRuntimeManaging {
    private(set) var enteredRoomIDs: [String] = []
    private(set) var leaveCallCount = 0

    func enterVisibleRoom(roomID: String) async {
        enteredRoomIDs.append(roomID)
    }

    func leaveVisibleRoom() async {
        leaveCallCount += 1
    }
}

private enum RuntimeTestError: Error {
    case cleanup
}
