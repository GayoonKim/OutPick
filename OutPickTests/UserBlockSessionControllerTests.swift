import Foundation
import Testing
@testable import OutPick

@MainActor
struct UserBlockSessionControllerTests {
    @Test func bootstrapUsesCacheThenReplacesWithServerSnapshot() async throws {
        let visibility = UserBlockVisibilityStore()
        let snapshots = FakeUserBlockSnapshotStore(values: ["me": ["cached"]])
        let repository = FakeUserBlockRelationRepository(result: .success(["remote"]))
        let controller = UserBlockSessionController(
            repository: repository,
            snapshotStore: snapshots,
            visibilityStore: visibility
        )

        try await controller.bootstrap(userID: "me")

        #expect(visibility.blockedUserIDs() == ["remote"])
        #expect(snapshots.values["me"] == ["remote"])
    }

    @Test func bootstrapFallsBackToLastSuccessfulCache() async throws {
        let visibility = UserBlockVisibilityStore()
        let snapshots = FakeUserBlockSnapshotStore(values: ["me": ["cached"]])
        let controller = UserBlockSessionController(
            repository: FakeUserBlockRelationRepository(result: .failure(TestError.offline)),
            snapshotStore: snapshots,
            visibilityStore: visibility
        )

        try await controller.bootstrap(userID: "me")

        #expect(visibility.blockedUserIDs() == ["cached"])
    }

    @Test func bootstrapFailsClosedWithoutCache() async {
        let visibility = UserBlockVisibilityStore(blockedUserIDs: ["stale"])
        let controller = UserBlockSessionController(
            repository: FakeUserBlockRelationRepository(result: .failure(TestError.offline)),
            snapshotStore: FakeUserBlockSnapshotStore(),
            visibilityStore: visibility
        )

        await #expect(throws: TestError.self) {
            try await controller.bootstrap(userID: "me")
        }
        #expect(visibility.blockedUserIDs().isEmpty)
        #expect(controller.activeUserID == nil)
    }

    @Test func successfulMutationUpdatesMemoryAndAccountSnapshot() async throws {
        let visibility = UserBlockVisibilityStore()
        let snapshots = FakeUserBlockSnapshotStore(values: ["me": []])
        let controller = UserBlockSessionController(
            repository: FakeUserBlockRelationRepository(result: .success([])),
            snapshotStore: snapshots,
            visibilityStore: visibility
        )
        try await controller.bootstrap(userID: "me")

        controller.applyServerMutation(userID: "me", targetUserID: "target", isBlocked: true)
        #expect(visibility.isBlocked("target"))
        #expect(snapshots.values["me"] == ["target"])

        controller.applyServerMutation(userID: "me", targetUserID: "target", isBlocked: false)
        #expect(!visibility.isBlocked("target"))
        #expect(snapshots.values["me"] == [])
    }

    @Test func staleBootstrapFailureDoesNotClearNewAccountVisibility() async throws {
        let visibility = UserBlockVisibilityStore()
        let repository = DeferredAccountSwitchRepository()
        let controller = UserBlockSessionController(
            repository: repository,
            snapshotStore: FakeUserBlockSnapshotStore(),
            visibilityStore: visibility
        )

        let staleBootstrap = Task {
            try await controller.bootstrap(userID: "old-user")
        }
        while await repository.hasPendingOldRequest() == false {
            await Task.yield()
        }

        try await controller.bootstrap(userID: "new-user")
        await repository.failOldRequest()
        try await staleBootstrap.value

        #expect(controller.activeUserID == "new-user")
        #expect(visibility.blockedUserIDs() == ["new-blocked"])
    }
}

private enum TestError: Error {
    case offline
}

private final class FakeUserBlockRelationRepository: UserBlockRelationReading {
    let result: Result<Set<UserID>, Error>

    init(result: Result<Set<String>, Error>) {
        self.result = result.map { Set($0.map(UserID.init(value:))) }
    }

    func fetchBlockedUserIDs(blockerUserID: UserID) async throws -> Set<UserID> {
        try result.get()
    }
}

private final class FakeUserBlockSnapshotStore: UserBlockSnapshotPersisting {
    var values: [String: Set<String>]

    init(values: [String: Set<String>] = [:]) {
        self.values = values
    }

    func load(userID: String) -> Set<String>? {
        values[userID]
    }

    func save(_ blockedUserIDs: Set<String>, userID: String) {
        values[userID] = blockedUserIDs
    }

    func removeAllSnapshots() {
        values.removeAll()
    }
}

private actor DeferredAccountSwitchRepository: UserBlockRelationReading {
    private var oldRequestContinuation: CheckedContinuation<Set<UserID>, Error>?

    func fetchBlockedUserIDs(blockerUserID: UserID) async throws -> Set<UserID> {
        if blockerUserID.value == "old-user" {
            return try await withCheckedThrowingContinuation { continuation in
                oldRequestContinuation = continuation
            }
        }
        return [UserID(value: "new-blocked")]
    }

    func hasPendingOldRequest() -> Bool {
        oldRequestContinuation != nil
    }

    func failOldRequest() {
        oldRequestContinuation?.resume(throwing: TestError.offline)
        oldRequestContinuation = nil
    }
}
