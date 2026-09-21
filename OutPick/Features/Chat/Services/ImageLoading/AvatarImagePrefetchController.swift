import Foundation
import Combine

@MainActor
final class AvatarImagePrefetchController: ObservableObject {
    private enum Status { case running, loaded, failed(Bool) }
    private struct Entry {
        let id: UUID
        var demand: AvatarViewportDemand
        var status: Status = .running
        var task: Task<Void, Never>?
        var removal: Task<Void, Never>?
        var wanted = true
    }
    private var entries: [String: Entry] = [:]
    private let load: (AvatarImageRequest) async throws -> Void
    private let sleep: (UInt64) async throws -> Void
    var activePaths: Set<String> { Set(entries.keys) }
    var loadingPaths: Set<String> {
        Set(entries.compactMap { path, entry in
            if case .running = entry.status { return path }
            return nil
        })
    }

    init(sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
         load: @escaping (AvatarImageRequest) async throws -> Void) {
        self.sleep = sleep; self.load = load
    }
    convenience init(manager: AvatarImageManaging) {
        self.init { request in _ = try await manager.loadAvatar(request) }
    }
    deinit { for entry in entries.values { entry.task?.cancel(); entry.removal?.cancel() } }

    func update(_ demands: [AvatarViewportDemand]) {
        let wanted = Set(demands.map { $0.request.path })
        for path in Array(entries.keys) where !wanted.contains(path) {
            guard entries[path]?.wanted == true else { continue }
            entries[path]?.wanted = false
            let id = entries[path]!.id
            entries[path]?.removal = Task { [weak self, sleep] in
                try? await sleep(300_000_000)
                guard !Task.isCancelled, let self, self.entries[path]?.id == id,
                      self.entries[path]?.wanted == false else { return }
                self.entries.removeValue(forKey: path)?.task?.cancel()
            }
        }
        for demand in demands {
            let path = demand.request.path
            guard var entry = entries[path] else { start(demand); continue }
            let upgrade = entry.demand.request.cachePolicy == .memoryOnly && demand.request.cachePolicy == .memoryAndDisk
            let newEvent = !entry.wanted || upgrade || !demand.visibleIDs.isSubset(of: entry.demand.visibleIDs)
            entry.removal?.cancel(); entry.removal = nil; entry.wanted = true
            entry.demand = demand
            entries[path] = entry
            switch entry.status {
            case .failed(let retryable) where retryable && newEvent: start(demand)
            case .loaded where upgrade: start(demand)
            default: break
            }
        }
    }

    func clear() {
        for entry in entries.values { entry.task?.cancel(); entry.removal?.cancel() }
        entries.removeAll()
    }

    private func start(_ demand: AvatarViewportDemand) {
        let path = demand.request.path, id = UUID()
        entries[path]?.task?.cancel()
        entries[path]?.removal?.cancel()
        entries[path] = Entry(id: id, demand: demand)
        entries[path]?.task = Task(priority: .utility) { [weak self, load] in
            do {
                try await ImageWorkContext.$current.withValue(ImageWorkContext(.prefetch)) { try await load(demand.request) }
                guard !Task.isCancelled, let self, self.entries[path]?.id == id else { return }
                self.entries[path]?.task = nil
                self.entries[path]?.status = .loaded
                if let latest = self.entries[path], latest.wanted,
                   demand.request.cachePolicy == .memoryOnly, latest.demand.request.cachePolicy == .memoryAndDisk {
                    self.start(latest.demand)
                }
            } catch {
                guard !Task.isCancelled, let self, self.entries[path]?.id == id else { return }
                self.entries[path]?.task = nil
                self.entries[path]?.status = .failed((error as? AvatarImageLoadingError) != .unavailable)
            }
        }
    }
}
