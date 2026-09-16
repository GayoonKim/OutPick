import Foundation

/// 화면이 원하는 이미지 집합만 보유한다. 실제 자원 제한과 동일 요청 합치기는 공용 캐시가 맡는다.
@MainActor
final class LookbookImagePrefetchController {
    private struct Job {
        let task: Task<Void, Never>
        var removal: Task<Void, Never>?
    }

    private let load: (LookbookAssetImageRequest) async -> Void
    private let graceNanoseconds: UInt64
    private var jobs: [String: Job] = [:]

    init(graceNanoseconds: UInt64 = 300_000_000,
         load: @escaping (LookbookAssetImageRequest) async -> Void) {
        self.graceNanoseconds = graceNanoseconds
        self.load = load
    }

    func update(_ requests: [LookbookAssetImageRequest]) {
        let wanted = Set(requests.map(\.identity))
        for key in jobs.keys where !wanted.contains(key) {
            guard jobs[key]?.removal == nil else { continue }
            jobs[key]?.removal = Task { [weak self, graceNanoseconds] in
                try? await Task.sleep(nanoseconds: graceNanoseconds)
                guard !Task.isCancelled else { return }
                self?.remove(key)
            }
        }
        for request in requests {
            let key = request.identity
            if jobs[key] != nil {
                jobs[key]?.removal?.cancel()
                jobs[key]?.removal = nil
                continue
            }
            let load = self.load
            let task = Task(priority: .utility) { await load(request) }
            jobs[key] = Job(task: task, removal: nil)
        }
    }

    func clear() {
        for job in jobs.values {
            job.removal?.cancel()
            job.task.cancel()
        }
        jobs.removeAll()
    }

    private func remove(_ key: String) {
        guard let job = jobs.removeValue(forKey: key) else { return }
        job.task.cancel()
    }
}
