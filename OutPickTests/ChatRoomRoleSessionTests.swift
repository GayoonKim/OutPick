import Foundation
import Testing
import UIKit
@testable import OutPick

@MainActor
struct ChatRoomRoleSessionTests {
    @Test func canceledObservationCannotRestoreManagementAfterStop() async {
        let observer = ChatRoomRoleObserveUseCaseFake()
        let session = ChatRoomRoleSession(
            roomID: "room-1", userID: "owner", cachedRole: .owner,
            observeUseCase: observer, notificationCenter: NotificationCenter()
        )
        session.start()
        observer.send(status: .member, role: .owner, source: .server)
        session.stop()
        await Task.yield()

        #expect(session.state.isObserving == false)
        #expect(session.state.isManagementEnabled == false)
        #expect(session.state.source == .cache)
    }

    @Test func oldGenerationCallbacksCannotOverwriteRestartedObservation() async {
        let observer = ChatRoomRoleObserveUseCaseFake()
        let session = ChatRoomRoleSession(
            roomID: "room-1", userID: "owner", cachedRole: .owner,
            observeUseCase: observer, notificationCenter: NotificationCenter()
        )
        session.start()
        session.stop()
        session.start()
        observer.send(status: .member, role: .member, source: .server)
        await Task.yield()
        observer.send(status: .member, role: .owner, source: .server, observationIndex: 0)
        observer.sendError(observationIndex: 0)
        await Task.yield()

        #expect(session.state.role == .member)
        #expect(session.state.isObserving)
        #expect(session.state.isManagementEnabled == false)
    }

    @Test func foregroundWaitsForFreshServerConfirmation() async {
        let center = NotificationCenter()
        let observer = ChatRoomRoleObserveUseCaseFake()
        let session = ChatRoomRoleSession(
            roomID: "room-1", userID: "owner", cachedRole: .owner,
            observeUseCase: observer, notificationCenter: center
        )
        session.start()
        observer.send(status: .member, role: .owner, source: .server)
        await Task.yield()
        #expect(session.state.isManagementEnabled)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        #expect(session.state.isObserving)
        #expect(session.state.isManagementEnabled == false)

        observer.send(status: .member, role: .owner, source: .server)
        await Task.yield()
        #expect(session.state.isManagementEnabled)
    }

    @Test func sharesOneObservationAndRequiresServerConfirmationForManagement() async {
        let observer = ChatRoomRoleObserveUseCaseFake()
        let session = ChatRoomRoleSession(
            roomID: "room-1",
            userID: "owner",
            cachedRole: .owner,
            observeUseCase: observer,
            notificationCenter: NotificationCenter()
        )

        session.start()
        session.start()

        #expect(observer.observeCount == 1)
        #expect(session.state.source == .cache)
        #expect(session.state.isManagementEnabled == false)

        observer.send(status: .member, role: .owner, source: .cache)
        await Task.yield()
        #expect(session.state.isManagementEnabled == false)

        observer.send(status: .member, role: .owner, source: .server)
        await Task.yield()
        #expect(session.state.isManagementEnabled)
    }

    @Test func backgroundCancelsAndForegroundCreatesOneNewObservation() async {
        let center = NotificationCenter()
        let observer = ChatRoomRoleObserveUseCaseFake()
        let session = ChatRoomRoleSession(
            roomID: "room-1",
            userID: "moderator",
            cachedRole: .moderator,
            observeUseCase: observer,
            notificationCenter: center
        )
        session.start()

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()
        #expect(observer.cancelCount == 1)
        #expect(session.state.isObserving == false)

        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        #expect(observer.observeCount == 2)
        #expect(session.state.isObserving)
    }

    @Test func legacyMemberProjectionPreservesCachedRoleUntilMigrationCompletes() async {
        let observer = ChatRoomRoleObserveUseCaseFake()
        let session = ChatRoomRoleSession(
            roomID: "room-1",
            userID: "owner",
            cachedRole: .owner,
            observeUseCase: observer,
            notificationCenter: NotificationCenter()
        )
        session.start()

        observer.send(status: .member, role: nil, source: .server)
        await Task.yield()

        #expect(session.state.role == .owner)
        #expect(session.state.isManagementEnabled)
    }

    @Test func missingJoinedRoomProjectionClearsRoleAndDisablesManagement() async {
        let observer = ChatRoomRoleObserveUseCaseFake()
        let session = ChatRoomRoleSession(
            roomID: "room-1",
            userID: "owner",
            cachedRole: .owner,
            observeUseCase: observer,
            notificationCenter: NotificationCenter()
        )
        session.start()

        observer.send(status: .joinable, role: nil, source: .server)
        await Task.yield()

        #expect(session.state.status == .joinable)
        #expect(session.state.role == nil)
        #expect(session.state.isManagementEnabled == false)
    }

    @Test func confirmedMutationUpdatesRoleWithoutStartingAnotherListener() {
        let observer = ChatRoomRoleObserveUseCaseFake()
        let session = ChatRoomRoleSession(
            roomID: "room-1",
            userID: "moderator",
            cachedRole: .member,
            observeUseCase: observer,
            notificationCenter: NotificationCenter()
        )
        session.start()

        session.applyConfirmedCurrentRole(.moderator)

        #expect(observer.observeCount == 1)
        #expect(session.state.role == .moderator)
        #expect(session.state.source == .mutation)
        #expect(session.state.isManagementEnabled)
    }
}

private final class ChatRoomRoleObserveUseCaseFake: ObserveChatRoomRoleUseCaseProtocol {
    private var updates: [@Sendable (ChatRoomRoleSnapshot) -> Void] = []
    private var errors: [@Sendable (Error) -> Void] = []
    private(set) var observeCount = 0
    private(set) var cancelCount = 0

    func observe(
        roomID: String,
        userID: String,
        onUpdate: @escaping @Sendable (ChatRoomRoleSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> ChatRoomRoleObservationCancelling {
        observeCount += 1
        updates.append(onUpdate)
        errors.append(onError)
        return ChatRoomRoleObservationCancellationSpy { [weak self] in
            self?.cancelCount += 1
        }
    }

    func fetchMemberRole(roomID: String, userID: String) async throws -> ChatRoomMemberRole? {
        nil
    }

    func send(
        status: ChatRoomAccessStatus,
        role: ChatRoomMemberRole?,
        source: ChatRoomRoleSnapshotSource,
        observationIndex: Int? = nil
    ) {
        let index = observationIndex ?? (updates.count - 1)
        guard updates.indices.contains(index) else { return }
        updates[index](ChatRoomRoleSnapshot(
            roomID: "room-1",
            status: status,
            role: role,
            source: source
        ))
    }

    func sendError(observationIndex: Int) {
        errors[observationIndex](NSError(domain: "role-test", code: 1))
    }
}

private final class ChatRoomRoleObservationCancellationSpy: ChatRoomRoleObservationCancelling {
    private let onCancel: () -> Void
    private var isCancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}
