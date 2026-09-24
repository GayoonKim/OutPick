import UIKit

/// 표시 회차는 셀 수명이나 요청 취소 유예와 독립적으로 유지한다.
@MainActor
final class ChatMediaViewportController {
    enum Presentation {
        case idle, loading, failed
        case image(UIImage)
    }
    private final class Entry {
        var path: String
        var visible = false
        var episode = 0
        var failedEpisode: Int?
        var image: UIImage?
        var generation = UUID()
        var tasks: [Task<Void, Never>] = []
        var priority: ImageRequestPriority?
        var releaseTask: Task<Void, Never>?
        init(path: String) { self.path = path }
        func cancel() {
            generation = UUID()
            tasks.forEach { $0.cancel() }
            tasks.removeAll()
            priority = nil
            releaseTask?.cancel()
            releaseTask = nil
        }
        deinit {
            tasks.forEach { $0.cancel() }
            releaseTask?.cancel()
        }
    }
    typealias Loader = (String, ImageRequestPriority) async throws -> UIImage
    private let load: Loader
    private let cached: (String) -> UIImage?
    private let delay: () async throws -> Void
    private var entries: [String: Entry] = [:]
    private var suspended = true
    private let diskPreparation: ChatDiskPreparationController
    var onChange: ((String, String, Presentation) -> Void)?

    init(cached: @escaping (String) -> UIImage? = { _ in nil }, load: @escaping Loader,
         canPrepareDisk: @escaping () -> Bool = { false }, prepareDisk: @escaping (String) async -> Void = { _ in },
         delay: @escaping () async throws -> Void = {
        try await Task.sleep(nanoseconds: 300_000_000)
    }) {
        self.load = load
        self.cached = cached
        self.delay = delay
        self.diskPreparation = ChatDiskPreparationController(
            maxConcurrent: nil,
            canPrepare: canPrepareDisk, prepare: prepareDisk)
    }

    func resume() { suspended = false }

    // 화면 배치 전에는 메시지 순서로 준비하고, 배치 후 실제 거리순 후보로 교체한다.
    func prepareDiskBeforeLayout(paths: [String]) { diskPreparation.update(paths: paths) }
    func stopDiskPreparation() { diskPreparation.suspend() }

    func update(items: [ChatMediaViewportItem], demands: [String: ImageRequestPriority], validIDs: Set<String>, cancelOutsideImmediately: Bool = false, diskPreparationPaths: [String]? = nil) {
        for id in Array(entries.keys) where !validIDs.contains(id) {
            entries.removeValue(forKey: id)?.cancel()
        }
        guard !suspended else { return }
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for (id, entry) in entries {
            let visible = demands[id] == .visible
            if visible && !entry.visible { entry.episode += 1 }
            entry.visible = visible
            if let item = itemsByID[id], item.path != entry.path {
                let preservesLocal = entry.path.hasPrefix("/") || entry.path.hasPrefix("file://")
                entry.cancel()
                if !preservesLocal { entry.image = nil }
                entry.path = item.path
                entry.failedEpisode = nil
            }
        }
        for (id, priority) in demands {
            guard let item = itemsByID[id] else { continue }
            let entry: Entry
            if let existing = entries[id] { entry = existing }
            else {
                entry = Entry(path: item.path)
                entry.visible = priority == .visible
                entry.episode = entry.visible ? 1 : 0
                entries[id] = entry
            }
            entry.releaseTask?.cancel()
            entry.releaseTask = nil
            if let image = entry.image { onChange?(id, entry.path, .image(image)); continue }
            if entry.tasks.isEmpty, let image = cached(entry.path) {
                entry.image = image
                entry.failedEpisode = nil
                ImageCacheMetrics.shared.mark("chatPreview.presentation", key: entry.path, outcome: "memoryImmediate")
                onChange?(id, entry.path, .image(image))
                continue
            }
            if !entry.tasks.isEmpty {
                if priority == .visible && entry.priority == .prefetch {
                    // 기존 소비자를 유지한 채 합류하여 마지막 소비자 취소 경합을 피한다.
                    start(id: id, entry: entry, priority: .visible)
                }
                onChange?(id, entry.path, .loading)
                continue
            }
            if let failed = entry.failedEpisode, !entry.visible || failed == entry.episode {
                onChange?(id, entry.path, .failed)
                continue
            }
            start(id: id, entry: entry, priority: priority)
        }
        for (id, entry) in entries where demands[id] == nil {
            guard !entry.tasks.isEmpty || entry.image != nil else { continue }
            if cancelOutsideImmediately {
                entry.cancel()
                entry.image = nil
                ImageCacheMetrics.shared.mark("chatPreview.presentation", key: entry.path, outcome: "fastScrollReleased")
                onChange?(id, entry.path, .idle)
                continue
            }
            guard entry.releaseTask == nil else { continue }
            let delay = delay
            entry.releaseTask = Task { [weak self, weak entry] in
                do { try await delay() } catch { return }
                guard !Task.isCancelled, let self, let entry, self.entries[id] === entry else { return }
                entry.cancel()
                entry.image = nil
                ImageCacheMetrics.shared.mark("chatPreview.presentation", key: entry.path, outcome: "released")
                self.onChange?(id, entry.path, .idle)
            }
        }
        if let diskPreparationPaths { diskPreparation.update(paths: diskPreparationPaths) }
    }

    private func start(id: String, entry: Entry, priority: ImageRequestPriority) {
        entry.priority = priority
        let generation = entry.generation
        let path = entry.path
        let load = load
        ImageCacheMetrics.shared.mark("chatPreview.presentation", key: path, outcome: "loading")
        onChange?(id, path, .loading)
        let task = Task { [weak self, weak entry] in
            let result: Result<UIImage, Error>
            do {
                result = .success(try await ImageCacheMetrics.shared.request("chatPreview.load", key: path) {
                    try await load(path, priority)
                })
            }
            catch { result = .failure(error) }
            guard !Task.isCancelled, let self, let entry,
                  self.entries[id] === entry, entry.generation == generation, entry.path == path else { return }
            entry.generation = UUID()
            entry.tasks.forEach { $0.cancel() }
            entry.tasks.removeAll()
            entry.priority = nil
            switch result {
            case .success(let image):
                entry.image = image
                entry.failedEpisode = nil
                ImageCacheMetrics.shared.mark("chatPreview.presentation", key: path, outcome: "image")
                self.onChange?(id, path, .image(image))
            case .failure(let error):
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.onChange?(id, path, .idle)
                } else {
                    entry.failedEpisode = entry.episode
                    ImageCacheMetrics.shared.mark("chatPreview.presentation", key: path, outcome: "failed")
                    self.onChange?(id, path, .failed)
                }
            }
        }
        entry.tasks.append(task)
    }

    func suspend() {
        suspended = true
        diskPreparation.suspend()
        for entry in entries.values {
            entry.cancel()
            entry.image = nil
        }
    }

    func endSession() {
        suspend()
        entries.removeAll()
    }
}

/// 최신 거리순으로 제한된 수만 준비하며 실제 디코딩은 공용 우선순위 게이트를 따른다.
@MainActor
final class ChatDiskPreparationController {
    private let canPrepare: () -> Bool
    private let prepare: (String) async -> Void
    private var paths: [String] = []
    private var attempted = Set<String>()
    private let maxConcurrent: Int?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var generation = UUID()

    init(maxConcurrent: Int? = 1, canPrepare: @escaping () -> Bool, prepare: @escaping (String) async -> Void) {
        self.maxConcurrent = maxConcurrent.map { max(1, $0) }
        self.canPrepare = canPrepare
        self.prepare = prepare
    }

    func update(paths: [String]) {
        self.paths = paths
        attempted.formIntersection(Set(paths))
        let valid = Set(paths)
        for path in Array(tasks.keys) where !valid.contains(path) {
            tasks.removeValue(forKey: path)?.cancel()
        }
        startNext()
    }

    private func startNext() {
        while maxConcurrent.map({ tasks.count < $0 }) ?? true, canPrepare(),
              let path = paths.first(where: { !attempted.contains($0) && tasks[$0] == nil }) {
            let generation = generation
            let prepare = prepare
            tasks[path] = Task { [weak self] in
                await prepare(path)
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.attempted.insert(path)
                self.tasks.removeValue(forKey: path)
                self.startNext()
            }
        }
    }

    func suspend() {
        generation = UUID()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        paths.removeAll()
        attempted.removeAll()
    }

    deinit { tasks.values.forEach { $0.cancel() } }
}
