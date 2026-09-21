import Foundation
import UIKit

/// 이미지 복사본 없이 즉시 메모리 조회의 세션·사진 무효화 경계만 보호한다.
final class AvatarImmediateReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private var denied = Set<String>()
    private var pending: [String: Int] = [:]

    init(enabled: Bool) { self.enabled = enabled }
    func update(enabled: Bool, denied: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled; self.denied = denied
    }
    func beginInvalidation(_ paths: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        for path in paths { pending[path, default: 0] += 1 }
    }
    func endInvalidation(_ paths: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        for path in paths {
            if let count = pending[path], count > 1 { pending[path] = count - 1 }
            else { pending.removeValue(forKey: path) }
        }
    }
    func read(path: String, image: () -> UIImage?) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        guard enabled, !denied.contains(path), pending[path] == nil else { return nil }
        return image()
    }
}

/// 세션 전환 동안 요청 입장을 막고 이전 callback과 저장이 새 세션으로 넘어가지 않게 한다.
actor AvatarImageSessionController {
    nonisolated let immediateReads: AvatarImmediateReadGate
    private var generation: UInt64 = 0
    private var acceptsRequests: Bool
    private var userID: String?
    private var resetTask: Task<Void, Never>?
    private var cancellations: [UUID: (path: String, cancel: @Sendable () -> Void)] = [:]
    private var invalidations: [String: Task<Void, Never>] = [:]
    private var profiles: [String: UserPublicProfile] = [:]
    private var retiredPaths = Set<String>()
    private var unavailablePaths = Set<String>()
    func markUnavailable(path: String, token: UInt64?) {
        guard acceptsRequests, token == generation else { return }
        unavailablePaths.insert(path)
        synchronizeImmediateReads()
    }
    func resetFailures(paths: [String]) {
        unavailablePaths.subtract(paths)
        synchronizeImmediateReads()
    }
    private func synchronizeImmediateReads() {
        immediateReads.update(enabled: acceptsRequests, denied: retiredPaths.union(unavailablePaths))
    }
    private let ownerDefaults: UserDefaults?
    private static let ownerKey = "avatarImageCache.ownerUserID"
    private var diskOwner: String?

    init(requiresSession: Bool = false, ownerDefaults: UserDefaults? = nil) {
        acceptsRequests = !requiresSession
        immediateReads = AvatarImmediateReadGate(enabled: !requiresSession)
        self.ownerDefaults = ownerDefaults
        diskOwner = ownerDefaults?.string(forKey: Self.ownerKey)
    }

    func token() -> UInt64? { acceptsRequests ? generation : nil }

    func transition(to userID: String?, clear: @escaping @Sendable () async -> Void) async {
        if acceptsRequests, let userID, self.userID == userID { return }
        generation += 1
        let expected = generation
        acceptsRequests = false
        synchronizeImmediateReads()
        self.userID = nil
        cancellations.values.forEach { $0.cancel() }
        cancellations.removeAll()
        profiles.removeAll()
        retiredPaths.removeAll()
        unavailablePaths.removeAll()
        let previous = resetTask
        let pendingInvalidations = Array(invalidations.values)
        invalidations.removeAll()
        let shouldClear = userID == nil || diskOwner != userID
        diskOwner = userID
        // 호출 Task가 취소돼도 정리는 끝낸다. 새 정리는 이전 정리 뒤에서 실행한다.
        let task = Task { [ownerDefaults] in
            await previous?.value
            for invalidation in pendingInvalidations { await invalidation.value }
            if shouldClear { await clear() }
            ownerDefaults?.set(userID, forKey: Self.ownerKey)
        }
        resetTask = task
        await task.value
        guard generation == expected else { return }
        resetTask = nil
        self.userID = userID
        acceptsRequests = userID != nil
        synchronizeImmediateReads()
    }

    func perform(path: String, operation: @escaping @Sendable () async throws -> UIImage?) async throws -> UIImage? {
        try Task.checkCancellation()
        guard acceptsRequests, !retiredPaths.contains(path) else { throw CancellationError() }
        guard !unavailablePaths.contains(path) else { throw AvatarImageLoadingError.unavailable }
        let expected = generation
        await invalidations[path]?.value
        guard acceptsRequests, generation == expected, !retiredPaths.contains(path) else { throw CancellationError() }
        try Task.checkCancellation()
        let id = UUID()
        let task = Task { try await operation() }
        cancellations[id] = (path, { task.cancel() })
        defer { cancellations.removeValue(forKey: id) }
        return try await withTaskCancellationHandler {
            let image: UIImage?
            do { image = try await task.value }
            catch {
                guard !Task.isCancelled, acceptsRequests, generation == expected, !retiredPaths.contains(path) else { throw CancellationError() }
                throw error
            }
            try Task.checkCancellation()
            guard acceptsRequests, generation == expected, !retiredPaths.contains(path) else { throw CancellationError() }
            return image
        } onCancel: { task.cancel() }
    }

    func observe(_ profile: UserPublicProfile, previous: UserPublicProfile?, token: UInt64?,
                 invalidate: @escaping @Sendable (String) async -> Void) async -> UserPublicProfile? {
        guard let token, acceptsRequests, token == generation else { return nil }
        let old = profiles[profile.userID] ?? previous
        if let oldDate = old?.updatedAt,
           profile.updatedAt == nil || profile.updatedAt! < oldDate { return old }
        let oldPaths = Set([old?.avatarThumbPath, old?.avatarOriginalPath].compactMap { $0 })
        let newPaths = Set([profile.avatarThumbPath, profile.avatarOriginalPath].compactMap { $0 })
        // 수정 시각이 없는 이전 snapshot으로 이미 제거한 경로를 되살리지 않는다.
        if let old, !retiredPaths.isDisjoint(with: newPaths),
           profile.updatedAt == nil || profile.updatedAt == old.updatedAt { return old }
        let removed = oldPaths.subtracting(newPaths)
        profiles[profile.userID] = profile
        immediateReads.beginInvalidation(removed)
        defer { immediateReads.endInvalidation(removed) }
        retiredPaths.formUnion(removed)
        retiredPaths.subtract(newPaths)
        synchronizeImmediateReads()
        for path in removed {
            cancellations.values.filter { $0.path == path }.forEach { $0.cancel() }
            let previousInvalidation = invalidations[path]
            invalidations[path] = Task { await previousInvalidation?.value; await invalidate(path) }
        }
        for path in removed { await invalidations[path]?.value }
        guard acceptsRequests, token == generation else { return nil }
        // 이전 무효화 대기 중 새 프로필이 도착했다면 마지막으로 수락한 값을 반환한다.
        return profiles[profile.userID]
    }
}
