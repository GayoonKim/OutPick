import Foundation
import Testing
@testable import OutPick

struct BannerPresentationQueueStateTests {
    @Test func presentsIndividuallyUntilFiveOutstandingItems() {
        var state = BannerPresentationQueueState(outstandingHardCap: 5)

        let first = state.enqueue(payload(index: 1, roomID: "room"))
        var queuedResults: [BannerPayload?] = []
        for index in 2...5 {
            queuedResults.append(state.enqueue(payload(index: index, roomID: "room")))
        }

        #expect(first == payload(index: 1, roomID: "room"))
        #expect(queuedResults.allSatisfy { $0 == nil })
        #expect(state.pending.count == 4)
    }

    @Test func overflowBecomesOneSummaryAfterIndividualQueue() {
        var state = BannerPresentationQueueState(outstandingHardCap: 5)
        for index in 1...7 {
            _ = state.enqueue(payload(index: index, roomID: "room"))
        }

        var presented: [BannerPayload] = []
        while let next = state.finishCurrent() {
            presented.append(next)
        }

        #expect(presented.map(\.title) == [
            "sender-2", "sender-3", "sender-4", "sender-5", "새 메시지 2개"
        ])
        #expect(presented.last?.body == "sender-7: message-7")
    }

    @Test func overflowSummaryIncludesRoomAndMessageCounts() {
        var state = BannerPresentationQueueState(outstandingHardCap: 1)
        _ = state.enqueue(payload(index: 1, roomID: "room-a"))
        _ = state.enqueue(payload(index: 2, roomID: "room-b"))
        _ = state.enqueue(payload(index: 3, roomID: "room-c"))

        let summary = state.finishCurrent()

        #expect(summary?.title == "2개 채팅방의 새 메시지 2개")
        #expect(summary?.roomID == "room-c")
    }

    @Test func resetClearsPendingAndOverflow() {
        var state = BannerPresentationQueueState(outstandingHardCap: 1)
        _ = state.enqueue(payload(index: 1, roomID: "room-a"))
        _ = state.enqueue(payload(index: 2, roomID: "room-b"))

        state.reset()
        let next = state.finishCurrent()

        #expect(state.current == nil)
        #expect(state.pending.isEmpty)
        #expect(next == nil)
    }

    private func payload(index: Int, roomID: String) -> BannerPayload {
        BannerPayload(
            roomID: roomID,
            title: "sender-\(index)",
            body: "message-\(index)",
            attachmentsCount: 0
        )
    }
}

struct BannerSubscriptionRetryPolicyTests {
    @Test func exponentialDelayIsCapped() {
        let policy = BannerSubscriptionRetryPolicy(baseDelay: 0.5, maxDelay: 8)

        #expect(policy.delay(forFailureAttempt: 1) == 0.5)
        #expect(policy.delay(forFailureAttempt: 2) == 1)
        #expect(policy.delay(forFailureAttempt: 3) == 2)
        #expect(policy.delay(forFailureAttempt: 5) == 8)
        #expect(policy.delay(forFailureAttempt: 10) == 8)
    }

    @Test @MainActor func recoverableOpenFailureRetriesSameRoomSubscription() async {
        let opener = BannerRoomSessionOpenerFake(failuresBeforeSuccess: 1)
        let manager = BannerManager(
            retryPolicy: BannerSubscriptionRetryPolicy(baseDelay: 0, maxDelay: 0),
            retrySleep: { _ in await Task.yield() }
        )
        manager.configure(realtimeSocketService: opener)

        manager.start(for: ["room"])
        await waitForBannerRetry {
            await opener.openCount >= 2
        }

        #expect(await opener.openCount == 2)
        manager.stopAll()
    }
}

private actor BannerRoomSessionOpenerFake: RealtimeBackgroundRoomSessionOpening {
    private var failuresRemaining: Int
    private(set) var openCount = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresRemaining = failuresBeforeSuccess
    }

    func openBackgroundRoomSession(for roomID: String) async throws -> ChatRoomSocketSession {
        openCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw NSError(
                domain: "SocketIO",
                code: -1001,
                userInfo: [NSLocalizedDescriptionKey: "NO ACK"]
            )
        }

        let stream = AsyncStream<ChatMessage> { _ in }
        return ChatRoomSocketSession(
            roomID: roomID,
            messages: stream,
            close: {}
        )
    }
}

private func waitForBannerRetry(
    attempts: Int = 1_000,
    condition: @escaping () async -> Bool
) async {
    for _ in 0..<attempts {
        if await condition() { return }
        await Task.yield()
    }
}
