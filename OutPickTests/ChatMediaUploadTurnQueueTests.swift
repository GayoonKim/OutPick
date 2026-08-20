import Foundation
import Testing
@testable import OutPick

struct ChatMediaUploadTurnQueueTests {
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
