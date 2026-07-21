import Testing
@testable import OutPick

struct ChatOpenRoomRequestRegistryTests {
    private enum TestError: Error {
        case fetchFailed
    }

    @Test @MainActor
    func sameRequestCreatesOneTaskAndSharesSuccess() async throws {
        let registry = ChatOpenRoomRequestRegistry<String, [String]>()
        var taskCreationCount = 0
        let makeTask: (ChatOpenRoomRequestState<String, [String]>.Request) -> Task<Void, Error> = { _ in
            taskCreationCount += 1
            return Task<Void, Error> { }
        }

        let owner = registry.acquire(
            stackID: "joined",
            roomID: "room-a",
            snapshot: ["root"],
            makeTask: makeTask
        )
        let follower = registry.acquire(
            stackID: "joined",
            roomID: "room-a",
            snapshot: ["root"],
            makeTask: makeTask
        )

        try await owner.task.value
        try await follower.task.value
        #expect(taskCreationCount == 1)
        registry.finish(stackID: "joined", token: owner.request.token)
    }

    @Test @MainActor
    func sameRequestCreatesOneTaskAndSharesActualError() async {
        let registry = ChatOpenRoomRequestRegistry<String, [String]>()
        var taskCreationCount = 0

        let makeTask: (ChatOpenRoomRequestState<String, [String]>.Request) -> Task<Void, Error> = { _ in
            taskCreationCount += 1
            return Task { throw TestError.fetchFailed }
        }
        let owner = registry.acquire(
            stackID: "joined",
            roomID: "room-a",
            snapshot: ["root"],
            makeTask: makeTask
        )
        let follower = registry.acquire(
            stackID: "joined",
            roomID: "room-a",
            snapshot: ["root"],
            makeTask: makeTask
        )

        #expect(taskCreationCount == 1)
        await expectFetchFailure(from: owner.task)
        await expectFetchFailure(from: follower.task)
        registry.finish(stackID: "joined", token: owner.request.token)
    }

    @Test @MainActor
    func failureCleanupAllowsSameRoomRetryWithNewTask() async {
        let registry = ChatOpenRoomRequestRegistry<String, [String]>()
        var taskCreationCount = 0
        let makeTask: (ChatOpenRoomRequestState<String, [String]>.Request) -> Task<Void, Error> = { _ in
            taskCreationCount += 1
            return Task { throw TestError.fetchFailed }
        }

        let first = registry.acquire(
            stackID: "joined",
            roomID: "room-a",
            snapshot: ["root"],
            makeTask: makeTask
        )
        await expectFetchFailure(from: first.task)
        registry.finish(stackID: "joined", token: first.request.token)

        let retry = registry.acquire(
            stackID: "joined",
            roomID: "room-a",
            snapshot: ["root"],
            makeTask: makeTask
        )

        #expect(taskCreationCount == 2)
        #expect(retry.request.token != first.request.token)
        registry.finish(stackID: "joined", token: retry.request.token)
    }

    @Test @MainActor
    func newerRoomSupersedesOnlyTheSameStack() {
        let registry = ChatOpenRoomRequestRegistry<String, [String]>()
        let makeTask: (ChatOpenRoomRequestState<String, [String]>.Request) -> Task<Void, Error> = { _ in
            Task<Void, Error> { }
        }
        let joinedA = registry.acquire(
            stackID: "joined",
            roomID: "room-a",
            snapshot: ["joined-root"],
            makeTask: makeTask
        )
        let openC = registry.acquire(
            stackID: "open",
            roomID: "room-c",
            snapshot: ["open-root"],
            makeTask: makeTask
        )
        let joinedB = registry.acquire(
            stackID: "joined",
            roomID: "room-b",
            snapshot: ["joined-root"],
            makeTask: makeTask
        )

        #expect(!registry.isCurrent(
            stackID: "joined",
            token: joinedA.request.token,
            snapshot: ["joined-root"]
        ))
        #expect(registry.isCurrent(
            stackID: "joined",
            token: joinedB.request.token,
            snapshot: ["joined-root"]
        ))
        #expect(registry.isCurrent(
            stackID: "open",
            token: openC.request.token,
            snapshot: ["open-root"]
        ))
    }

    @MainActor
    private func expectFetchFailure(from task: Task<Void, Error>) async {
        do {
            try await task.value
            Issue.record("fetch 오류가 호출자에게 전달되지 않았습니다.")
        } catch TestError.fetchFailed {
            // 예상한 실제 오류다.
        } catch {
            Issue.record("예상하지 못한 오류가 전달됐습니다: \(error)")
        }
    }
}
