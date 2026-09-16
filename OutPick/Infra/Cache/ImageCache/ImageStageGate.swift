import Foundation

/// 작업 수 또는 바이트를 예약한다. 취소/지급 경합은 actor 안에서 한 번만 끝낸다.
actor ImageStageGate {
    enum Kind: Sendable { case standard, read, write }
    struct Lease: Sendable {
        let id: UUID
        let gate: ImageStageGate
        func release() async { await gate.release(id) }
        func reduce(to amount: Int) async { await gate.reduce(id, to: amount) }
    }
    struct Snapshot: Sendable {
        let used: Int
        let active: Int
        let waiting: Int
        let writes: Int
    }
    private struct Waiter {
        let id: UUID
        let amount: Int
        let kind: Kind
        let context: ImageWorkContext?
        let continuation: CheckedContinuation<Lease, Error>
        let metric: ImageCacheMetrics.Span?
    }
    private struct Active {
        var amount: Int
        let kind: Kind
        let metric: ImageCacheMetrics.Span?
    }

    let capacity: Int
    private let maxWrites: Int
    private let name: String
    private var queue: [Waiter] = []
    private var active: [UUID: Active] = [:]
    private var used = 0
    private var writes = 0
    private var lastWasRead = false

    init(_ capacity: Int, name: String, maxWrites: Int = .max) {
        self.capacity = max(1, capacity)
        self.maxWrites = max(1, maxWrites)
        self.name = name
    }

    func acquire(_ amount: Int = 1, kind: Kind = .standard, context: ImageWorkContext? = ImageWorkContext.current) async throws -> Lease {
        guard amount > 0, amount <= capacity else { throw ImageCachePipelineError.reservationTooLarge }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let lease = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Lease, Error>) in
                queue.append(Waiter(id: id, amount: amount, kind: kind, context: context, continuation: continuation, metric: ImageCacheMetrics.shared.begin("\(name).wait")))
                drain()
            }
            if Task.isCancelled {
                release(id)
                throw CancellationError()
            }
            return lease
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func reprioritize() { drain() }
    func withPermit<T>(kind: Kind = .standard, operation: @Sendable () async throws -> T) async throws -> T {
        let lease = try await acquire(kind: kind)
        do {
            try Task.checkCancellation()
            let result = try await operation()
            await lease.release()
            return result
        } catch {
            await lease.release()
            throw error
        }
    }
    func snapshot() -> Snapshot { Snapshot(used: used, active: active.count, waiting: queue.count, writes: writes) }

    private func cancel(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let waiter = queue.remove(at: index)
        ImageCacheMetrics.shared.end(waiter.metric, outcome: "cancelled")
        waiter.continuation.resume(throwing: CancellationError())
        drain()
    }

    private func release(_ id: UUID) {
        guard let entry = active.removeValue(forKey: id) else { return }
        used -= entry.amount
        if entry.kind == .write { writes -= 1 }
        ImageCacheMetrics.shared.end(entry.metric)
        reportUsage()
        drain()
    }

    private func reduce(_ id: UUID, to amount: Int) {
        guard var entry = active[id] else { return }
        let updated = max(0, min(amount, entry.amount))
        used -= entry.amount - updated
        entry.amount = updated
        active[id] = entry
        reportUsage()
        drain()
    }

    private func drain() {
        while true {
            let eligible = queue.indices.filter {
                queue[$0].amount <= capacity - used && (queue[$0].kind != .write || writes < maxWrites)
            }
            guard !eligible.isEmpty else { return }
            // 읽기를 우선하되 읽기가 한 번 입장한 뒤에는 대기 쓰기에도 기회를 준다.
            let fairWrite = lastWasRead ? eligible.first { queue[$0].kind == .write } : nil
            let selected = fairWrite ?? eligible.max {
                let left = queue[$0], right = queue[$1]
                let lp = left.context?.priority.rawValue ?? ImageRequestPriority.prefetch.rawValue
                let rp = right.context?.priority.rawValue ?? ImageRequestPriority.prefetch.rawValue
                if lp != rp { return lp < rp }
                if left.kind == .read && right.kind == .write { return false }
                if left.kind == .write && right.kind == .read { return true }
                return $0 > $1
            }!
            let waiter = queue.remove(at: selected)
            used += waiter.amount
            if waiter.kind == .write { writes += 1 }
            if waiter.kind != .standard { lastWasRead = waiter.kind == .read }
            ImageCacheMetrics.shared.end(waiter.metric, outcome: "acquired")
            active[waiter.id] = Active(amount: waiter.amount, kind: waiter.kind, metric: ImageCacheMetrics.shared.begin("\(name).active"))
            waiter.continuation.resume(returning: Lease(id: waiter.id, gate: self))
            reportUsage()
        }
    }

    private func reportUsage() {
        ImageCacheMetrics.shared.mark("\(name).reserved", outcome: "active_\(active.count)_waiting_\(queue.count)", bytes: used)
    }
}
