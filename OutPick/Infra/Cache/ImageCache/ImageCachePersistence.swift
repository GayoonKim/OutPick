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
            await release?()
            return
        }
        pending[key]?.task.cancel()
        let id = UUID()
        let task = Task {
            await ImageWorkContext.$current.withValue(ImageWorkContext(.prefetch)) {
                await disk.write(payload: payload, forKey: key, revision: revision)
            }
            await release?()
            self.finished(key: key, id: id)
        }
        pending[key] = Pending(id: id, revision: revision, task: task)
    }

    func flush() async {
        let tasks = pending.values.map(\.task)
        for task in tasks { await task.value }
    }

    private func finished(key: String, id: UUID) {
        guard pending[key]?.id == id else { return }
        pending.removeValue(forKey: key)
    }
}
