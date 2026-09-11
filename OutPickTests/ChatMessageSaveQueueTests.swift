import Foundation
import Testing
@testable import OutPick

struct ChatMessageSaveQueueTests {
    @Test func invalidationDuringWriteStopsConfirmationAndPendingWrites() async {
        let gate = SaveGate()
        let session = ChatMessageCacheSession()
        let queue = ChatMessageSaveQueue(session: session)
        await queue.enqueue(message(1), save: { _ in await gate.save() }, confirm: { _ in await gate.confirm() })
        await gate.waitForStart()
        await queue.enqueue(message(2), save: { _ in await gate.save() }, confirm: { _ in await gate.confirm() })
        session.invalidate()
        await gate.release()
        await queue.waitUntilIdle()
        #expect(await gate.writes == 1)
        #expect(await gate.confirmations == 0)
    }

    @Test func duplicatesDuringSuspendedWriteAreCoalesced() async {
        let gate = SaveGate()
        let queue = ChatMessageSaveQueue(session: ChatMessageCacheSession())
        await queue.enqueue(message(1), save: { _ in await gate.save() }, confirm: { _ in await gate.confirm() })
        await gate.waitForStart()
        for _ in 0..<100 {
            await queue.enqueue(message(1), save: { _ in await gate.save() }, confirm: { _ in await gate.confirm() })
        }
        await gate.release()
        await queue.waitUntilIdle()
        #expect(await gate.writes == 1)
        #expect(await gate.confirmations == 1)
    }
    @Test func reopeningRoomDoesNotRevivePreviousLease() {
        let session = ChatMessageCacheSession()
        let old = session.snapshot(roomID: "room")
        session.invalidate(roomID: "room")
        session.activate(roomID: "room")
        let current = session.snapshot(roomID: "room")
        #expect(!old.isValid(roomID: "room"))
        #expect(current.isValid(roomID: "room"))
        session.invalidate()
        #expect(!current.isValid(roomID: "room"))
    }
    private func message(_ seq: Int64) -> ChatMessage {
        ChatMessage(ID: "m\(seq)", seq: seq, roomID: "room", senderUID: "user",
            senderNickname: "사용자", msg: "본문", sentAt: nil, attachments: [], replyPreview: nil)
    }

    @Test func retriesExactlyFiveTimesAndNeverConfirmsFailedWrite() async {
        let spy = SaveSpy(failures: 5)
        let queue = ChatMessageSaveQueue(session: ChatMessageCacheSession())
        await queue.enqueue(message(1), save: { try await spy.save($0) }, confirm: { await spy.confirm($0) })
        await queue.waitUntilIdle()
        #expect(await spy.attempts == 5)
        #expect(await spy.confirmations == 0)
    }

    @Test func fifthSuccessConfirmsAndInvalidatedRoomNeverWrites() async {
        let spy = SaveSpy(failures: 4)
        let session = ChatMessageCacheSession()
        let queue = ChatMessageSaveQueue(session: session)
        await queue.enqueue(message(1), save: { try await spy.save($0) }, confirm: { await spy.confirm($0) })
        await queue.waitUntilIdle()
        #expect(await spy.attempts == 5)
        #expect(await spy.confirmations == 1)
        session.invalidate(roomID: "room")
        await queue.enqueue(message(2), save: { try await spy.save($0) }, confirm: { await spy.confirm($0) })
        await queue.waitUntilIdle()
        #expect(await spy.attempts == 5)
    }

    @Test func thousandMessagesDrainWithoutDroppingOrParallelWrites() async {
        let spy = SaveSpy(failures: 0)
        let queue = ChatMessageSaveQueue(session: ChatMessageCacheSession())
        for seq in 1...1_000 {
            await queue.enqueue(message(Int64(seq)), save: { try await spy.save($0) }, confirm: { await spy.confirm($0) })
        }
        await queue.waitUntilIdle()
        #expect(await spy.attempts == 1_000)
        #expect(await spy.confirmations == 1_000)
        #expect(await spy.maximumConcurrentWrites == 1)
    }
}

private actor SaveSpy {
    private var failures: Int
    private(set) var attempts = 0
    private(set) var confirmations = 0
    private var activeWrites = 0
    private(set) var maximumConcurrentWrites = 0
    init(failures: Int) { self.failures = failures }
    func save(_ message: ChatMessage) async throws {
        attempts += 1
        if failures > 0 { failures -= 1; throw ChatMessagePageError.incomplete }
        activeWrites += 1
        maximumConcurrentWrites = max(maximumConcurrentWrites, activeWrites)
        await Task.yield()
        activeWrites -= 1
    }
    func confirm(_ message: ChatMessage) { confirmations += 1 }
}

private actor SaveGate {
    private var resumeWrite: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var writes = 0
    private(set) var confirmations = 0
    func save() async {
        writes += 1
        await withCheckedContinuation { continuation in
            resumeWrite = continuation
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
        }
    }
    func waitForStart() async {
        if writes > 0 { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func release() { resumeWrite?.resume(); resumeWrite = nil }
    func confirm() { confirmations += 1 }
}
