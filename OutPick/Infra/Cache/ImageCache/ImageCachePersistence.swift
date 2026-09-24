import Foundation

/// 화면 Task와 독립적으로 저장을 소유한다. 입장 예산은 다운로드 전에 확보되어 있다.
actor ImageCachePersistence {
    private struct Pending {
        let id: UUID
        let revision: UInt64
        let task: Task<Void, Never>
    }
    private var pending: [String: Pending] = [:]
    private let disk: ImageCacheDiskStore
    init(disk: ImageCacheDiskStore) { self.disk = disk }

    func enqueue(_ payload: ImageCachePayload, key: String, revision: UInt64, release: (@Sendable () async -> Void)?) async {
        if let current = pending[key], current.revision > revision {
            ImageCacheMetrics.shared.mark("persistence", key: key, outcome: "stale")
            await release?()
            return
        }
        if let previous = pending[key] {
            ImageCacheMetrics.shared.mark("persistence", key: key, outcome: "superseded")
            previous.task.cancel()
        }
        let id = UUID()
        let metric = ImageCacheMetrics.shared.begin("persistence.pending", key: key)
        let task = Task {
            let result = await ImageWorkContext.$current.withValue(ImageWorkContext(.prefetch)) {
                await disk.write(payload: payload, forKey: key, revision: revision)
            }
            await release?()
            ImageCacheMetrics.shared.end(metric, outcome: result.rawValue)
            self.finished(key: key, id: id)
        }
        pending[key] = Pending(id: id, revision: revision, task: task)
    }

    func flush() async {
        let tasks = pending.values.map(\.task)
        for task in tasks { await task.value }
    }

    /// 조회 전에 동일 세대의 같은 키만 기다린다. 다른 파일의 저장을 막거나 취소하지 않는다.
    func wait(forKey key: String, revision: UInt64) async throws {
        while let current = pending[key], current.revision == revision {
            try Task.checkCancellation()
            let metric = ImageCacheMetrics.shared.begin("persistence.join", key: key)
            await current.task.value
            ImageCacheMetrics.shared.end(metric, outcome: Task.isCancelled ? "cancelled" : "finished")
            try Task.checkCancellation()
        }
    }

    private func finished(key: String, id: UUID) {
        guard pending[key]?.id == id else { return }
        pending.removeValue(forKey: key)
    }
}
