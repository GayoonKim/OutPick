import Foundation
import Testing
@testable import OutPick

struct ChatMediaUploadTurnQueueTests {
    @Test func registeredSelectionOrderWinsOverTaskArrivalOrder() async throws {
        let queue = ChatMediaUploadTurnQueue()
        await queue.register(lane: .images, uploadIDs: ["first30", "second30", "last10"])
        let last = Task { try await queue.acquire(lane: .images, uploadID: "last10") }
        let second = Task { try await queue.acquire(lane: .images, uploadID: "second30") }
        try await queue.acquire(lane: .images, uploadID: "first30")
        #expect(await queue.snapshot(lane: .images).activeUploadIDs == ["first30"])
        #expect(await queue.snapshot(lane: .images).waitingUploadIDs == ["second30", "last10"])
        await queue.release(lane: .images, uploadID: "first30")
        try await second.value
        #expect(await queue.snapshot(lane: .images).activeUploadIDs == ["second30"])
        await queue.release(lane: .images, uploadID: "second30")
        try await last.value
        await queue.release(lane: .images, uploadID: "last10")
    }

    @Test func removingUnstartedRegisteredBatchDoesNotBlockFollowingBatch() async throws {
        let queue = ChatMediaUploadTurnQueue()
        await queue.register(lane: .images, uploadIDs: ["removed", "next"])
        let next = Task { try await queue.acquire(lane: .images, uploadID: "next") }
        await queue.release(lane: .images, uploadID: "removed")
        try await next.value
        #expect(await queue.snapshot(lane: .images).activeUploadIDs == ["next"])
        await queue.release(lane: .images, uploadID: "next")
    }

    @Test func boundedParallelReleaseIsIdempotent() async throws {
        let queue = ChatMediaUploadTurnQueue(imageLimit: 2)
        try await queue.acquire(lane: .images, uploadID: "a")
        try await queue.acquire(lane: .images, uploadID: "b")
        let c = Task { try await queue.acquire(lane: .images, uploadID: "c") }
        await waitUntil(queue: queue, lane: .images, waitingCount: 1)
        let d = Task { try await queue.acquire(lane: .images, uploadID: "d") }
        await waitUntil(queue: queue, lane: .images, waitingCount: 2)
        await queue.release(lane: .images, uploadID: "b")
        try await c.value
        await queue.release(lane: .images, uploadID: "b")
        #expect(await queue.snapshot(lane: .images).activeUploadIDs == ["a", "c"])
        #expect(await queue.snapshot(lane: .images).waitingUploadIDs == ["d"])
        await queue.release(lane: .images, uploadID: "a")
        try await d.value
        await queue.release(lane: .images, uploadID: "c")
        await queue.release(lane: .images, uploadID: "d")
    }

    @Test func duplicateIdentityDoesNotCreateSecondOwner() async throws {
        let queue = ChatMediaUploadTurnQueue(imageLimit: 2)
        try await queue.acquire(lane: .images, uploadID: "a")
        do {
            try await queue.acquire(lane: .images, uploadID: "a")
            Issue.record("같은 identity의 중복 실행을 허용하면 안 됩니다.")
        } catch ChatMediaUploadTurnError.duplicateRequest { }
        #expect(await queue.snapshot(lane: .images).activeUploadIDs == ["a"])
        await queue.release(lane: .images, uploadID: "a")
    }

    @Test func sameLaneRunsInFIFOOrder() async throws {
        let queue = ChatMediaUploadTurnQueue()
        try await queue.acquire(lane: .images, uploadID: "first")

        let second = Task {
            try await queue.acquire(lane: .images, uploadID: "second")
        }
        await waitUntil(queue: queue, lane: .images, waitingCount: 1)
        let third = Task {
            try await queue.acquire(lane: .images, uploadID: "third")
        }
        await waitUntil(queue: queue, lane: .images, waitingCount: 2)

        await queue.release(lane: .images, uploadID: "first")
        try await second.value
        #expect(await queue.snapshot(lane: .images) == .init(
            activeUploadID: "second",
            waitingUploadIDs: ["third"]
        ))

        await queue.release(lane: .images, uploadID: "second")
        try await third.value
        #expect(await queue.snapshot(lane: .images).activeUploadID == "third")
        await queue.release(lane: .images, uploadID: "third")
    }

    @Test func imageAndVideoLanesDoNotBlockEachOther() async throws {
        let queue = ChatMediaUploadTurnQueue()

        try await queue.acquire(lane: .images, uploadID: "image")
        try await queue.acquire(lane: .video, uploadID: "video")

        #expect(await queue.snapshot(lane: .images).activeUploadID == "image")
        #expect(await queue.snapshot(lane: .video).activeUploadID == "video")
        await queue.release(lane: .images, uploadID: "image")
        await queue.release(lane: .video, uploadID: "video")
    }

    @Test func canceledWaiterDoesNotConsumeNextTurn() async throws {
        let queue = ChatMediaUploadTurnQueue()
        try await queue.acquire(lane: .images, uploadID: "first")
        let canceled = Task {
            try await queue.acquire(lane: .images, uploadID: "canceled")
        }
        await waitUntil(queue: queue, lane: .images, waitingCount: 1)
        let next = Task {
            try await queue.acquire(lane: .images, uploadID: "next")
        }
        await waitUntil(queue: queue, lane: .images, waitingCount: 2)

        canceled.cancel()
        do {
            try await canceled.value
            Issue.record("취소된 대기 항목은 획득에 성공하면 안 됩니다.")
        } catch is CancellationError {
        } catch {
            Issue.record("예상하지 못한 오류: \(error)")
        }
        await queue.release(lane: .images, uploadID: "first")
        try await next.value

        #expect(await queue.snapshot(lane: .images).activeUploadID == "next")
        await queue.release(lane: .images, uploadID: "next")
    }

    private func waitUntil(
        queue: ChatMediaUploadTurnQueue,
        lane: ChatMediaUploadTurnLane,
        waitingCount: Int
    ) async {
        for _ in 0..<1_000 {
            if await queue.snapshot(lane: lane).waitingUploadIDs.count == waitingCount {
                return
            }
            await Task.yield()
        }
        Issue.record("대기열 상태가 제한 시간 안에 갱신되지 않았습니다.")
    }
}
