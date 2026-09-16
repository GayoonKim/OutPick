import Foundation
import CryptoKit

/// 로딩 정책을 바꾸지 않는 선택적 계측. 시간은 monotonic clock 기준이며 화면 렌더 완료를 뜻하지 않는다.
final class ImageCacheMetrics: @unchecked Sendable {
    struct Span: Sendable {
        let id: UUID
    }

    struct Event: Sendable {
        let sequence: Int
        let time: TimeInterval
        let id: UUID
        let parent: UUID?
        let key: String
        let stage: String
        let action: String
        let outcome: String
        let milliseconds: Double
        let active: Int
        let bytes: Int
        let heldBytes: Int
    }

    private struct Entry {
        let parent: UUID?
        let key: String
        let stage: String
        let started: TimeInterval
        let bytes: Int
    }

    @TaskLocal static var requestID: UUID?
    @TaskLocal static var consumer = "caller"

    static let shared: ImageCacheMetrics = {
        #if DEBUG
        let enabled = ProcessInfo.processInfo.environment["OUTPICK_IMAGE_BASELINE"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-ImageLoadingBaseline")
        #else
        let enabled = false
        #endif
        return ImageCacheMetrics(enabled: enabled) { event in
            print("[ImageBaseline] seq=\(event.sequence) t=\(event.time) id=\(event.id) parent=\(event.parent?.uuidString ?? "none") key=\(event.key) stage=\(event.stage) action=\(event.action) outcome=\(event.outcome) ms=\(event.milliseconds) active=\(event.active) bytes=\(event.bytes) heldBytes=\(event.heldBytes)")
        }
    }()

    private let enabled: Bool
    private let clock: @Sendable () -> TimeInterval
    private let sink: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var counts: [String: Int] = [:]
    private var heldBytes = 0
    private var sequence = 0

    init(enabled: Bool, clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, sink: @escaping @Sendable (Event) -> Void) {
        self.enabled = enabled
        self.clock = clock
        self.sink = sink
    }

    func begin(_ stage: String, key: String = "", parent: UUID? = ImageCacheMetrics.requestID, bytes: Int = 0) -> Span? {
        guard enabled else { return nil }
        let id = UUID()
        // 원본 URL, 서명 query, 사용자 ID를 로그에 남기지 않는다.
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        lock.lock()
        let now = clock()
        let entry = Entry(parent: parent, key: digest, stage: stage, started: now, bytes: max(0, bytes))
        entries[id] = entry
        counts[stage, default: 0] += 1
        heldBytes += entry.bytes
        let event = makeEvent(id: id, entry: entry, time: now, action: "begin", outcome: "", bytes: entry.bytes)
        lock.unlock()
        sink(event)
        return Span(id: id)
    }

    func end(_ span: Span?, outcome: String = "completed", bytes: Int = 0) {
        guard let span else { return }
        lock.lock()
        guard let entry = entries.removeValue(forKey: span.id) else {
            lock.unlock()
            return
        }
        counts[entry.stage, default: 0] -= 1
        heldBytes -= entry.bytes
        let event = makeEvent(id: span.id, entry: entry, time: clock(), action: "end", outcome: outcome, bytes: bytes)
        lock.unlock()
        sink(event)
    }

    func mark(_ stage: String, key: String = "", parent: UUID? = ImageCacheMetrics.requestID, outcome: String = "", bytes: Int = 0) {
        let span = begin(stage, key: key, parent: parent)
        end(span, outcome: outcome, bytes: bytes)
    }

    private func makeEvent(id: UUID, entry: Entry, time: TimeInterval, action: String, outcome: String, bytes: Int) -> Event {
        sequence += 1
        return Event(sequence: sequence, time: time, id: id, parent: entry.parent, key: entry.key, stage: entry.stage, action: action, outcome: outcome, milliseconds: (time - entry.started) * 1000, active: counts[entry.stage, default: 0], bytes: bytes, heldBytes: heldBytes)
    }

    func request<T>(_ stage: String = "request", key: String, operation: () async throws -> T) async rethrows -> T {
        guard enabled else { return try await operation() }
        let span = begin("\(stage).\(Self.consumer)", key: key)
        return try await withTaskCancellationHandler {
            try await Self.$requestID.withValue(span?.id) {
                do {
                    let value = try await operation()
                    end(span, outcome: Task.isCancelled ? "returnedAfterCancellation" : "success")
                    return value
                } catch {
                    end(span, outcome: error is CancellationError || Task.isCancelled ? "cancelled" : "failure")
                    throw error
                }
            }
        } onCancel: {
            // 취소를 관찰만 한다. 기존 공용 Task나 SDK 요청을 추가로 취소하지 않는다.
            let signal = self.begin("callerCancellation", key: key, parent: span?.id)
            self.end(signal)
        }
    }
}
