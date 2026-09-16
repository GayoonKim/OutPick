import Foundation
import Testing
@testable import OutPick

struct ImageCacheMetricsTests {
    @Test func disabledMetricsDoNotReadClockOrEmitEvents() {
        let recorder = ImageMetricRecorder()
        let metrics = ImageCacheMetrics(enabled: false, clock: {
            recorder.recordClockRead()
            return 0
        }, sink: recorder.append)
        let span = metrics.begin("decode", key: "private-url")
        metrics.end(span)
        #expect(span == nil)
        #expect(recorder.events.isEmpty)
        #expect(recorder.clockReads == 0)
    }

    @Test func duplicateEndDoesNotReleaseAnotherSpansBytes() {
        let recorder = ImageMetricRecorder()
        let metrics = ImageCacheMetrics(enabled: true, sink: recorder.append)
        let first = metrics.begin("data", bytes: 10)
        let second = metrics.begin("data", bytes: 20)
        metrics.end(first)
        metrics.end(first)
        metrics.end(second)
        let events = recorder.events.sorted { $0.sequence < $1.sequence }
        #expect(events.map(\.active) == [1, 2, 1, 0])
        #expect(events.map(\.heldBytes) == [10, 30, 20, 0])
    }

    @Test func concurrentSpansBalanceAndPreserveUniqueSequence() async {
        let recorder = ImageMetricRecorder()
        let metrics = ImageCacheMetrics(enabled: true, sink: recorder.append)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let span = metrics.begin("decode", bytes: 64)
                    metrics.end(span)
                }
            }
        }
        let events = recorder.events.sorted { $0.sequence < $1.sequence }
        #expect(events.count == 200)
        #expect(Set(events.map(\.sequence)).count == 200)
        #expect(events.allSatisfy { $0.active >= 0 && $0.heldBytes >= 0 })
        #expect(events.last?.active == 0)
        #expect(events.last?.heldBytes == 0)
    }

    @Test func requestPreservesResultAndErrorAndRestoresContext() async {
        let recorder = ImageMetricRecorder()
        let metrics = ImageCacheMetrics(enabled: true, sink: recorder.append)
        let secret = "https://example.invalid/image?signature=secret"
        let result = await metrics.request(key: secret) {
            metrics.mark("child", key: secret)
            return 42
        }
        #expect(result == 42)
        #expect(ImageCacheMetrics.requestID == nil)
        enum ExpectedFailure: Error { case sample }
        do {
            _ = try await metrics.request(key: secret) { throw ExpectedFailure.sample }
            Issue.record("오류가 그대로 전달되어야 합니다.")
        } catch {
            #expect(error is ExpectedFailure)
        }
        let events = recorder.events
        let root = events.first { $0.stage == "request.caller" && $0.action == "begin" }
        #expect(events.first { $0.stage == "child" }?.parent == root?.id)
        #expect(events.allSatisfy { !$0.key.contains("signature") && $0.key != secret })
        #expect(events.last?.outcome == "failure")
    }
}

private final class ImageMetricRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [ImageCacheMetrics.Event] = []
    private var storedClockReads = 0

    var events: [ImageCacheMetrics.Event] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    var clockReads: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedClockReads
    }

    func recordClockRead() {
        lock.lock()
        storedClockReads += 1
        lock.unlock()
    }

    func append(_ event: ImageCacheMetrics.Event) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }
}
