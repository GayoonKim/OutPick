import Foundation
import UIKit

/// 화면에는 사용처 정책만 묶어 전달한다. 캐시와 세션은 앱의 한 서비스가 소유한다.
final class ScopedAvatarImageManager: AvatarImageManaging {
    @MainActor func cachedAvatarImmediately(for path: String) -> UIImage? {
        base.cachedAvatarImmediately(for: path)
    }
    @MainActor var avatarCachePolicy: AvatarImageCachePolicy { policy() }
    func resetAvatarFailures(paths: [String]) async { await base.resetAvatarFailures(paths: paths) }
    private let base: AvatarImageManaging
    private let policy: @MainActor () -> AvatarImageCachePolicy

    init(base: AvatarImageManaging, policy: @escaping @MainActor () -> AvatarImageCachePolicy) {
        self.base = base
        self.policy = policy
    }

    func cachedAvatar(for path: String) async -> UIImage? {
        await base.cachedAvatar(AvatarImageRequest(path: path, representation: .thumbnail, cachePolicy: policy()))
    }
    func loadAvatar(for path: String, maxBytes: Int) async throws -> UIImage {
        try await base.loadAvatar(AvatarImageRequest(path: path, representation: .thumbnail, cachePolicy: policy()))
    }
    func cachedAvatar(_ request: AvatarImageRequest) async -> UIImage? { await base.cachedAvatar(request) }
    func loadAvatar(_ request: AvatarImageRequest) async throws -> UIImage { try await base.loadAvatar(request) }
    func loadOriginalAvatar(for path: String) async throws -> UIImage { try await base.loadOriginalAvatar(for: path) }
    func prefetchAvatars(paths: [String], maxBytes: Int, maxConcurrent: Int) async {
        let cachePolicy = await policy()
        let requests = Array(Set(paths)).map { AvatarImageRequest(path: $0, representation: .thumbnail, cachePolicy: cachePolicy) }
        await withTaskGroup(of: Void.self) { group in
            var iterator = requests.makeIterator()
            func enqueue() {
                guard !Task.isCancelled, let request = iterator.next() else { return }
                group.addTask { [base] in
                    await ImageWorkContext.$current.withValue(ImageWorkContext(.prefetch)) {
                        _ = try? await base.loadAvatar(request)
                    }
                }
            }
            for _ in 0..<min(max(1, maxConcurrent), requests.count) { enqueue() }
            while await group.next() != nil { enqueue() }
        }
    }
    func storeAvatarDataToCache(_ data: Data, for path: String) async throws { try await base.storeAvatarDataToCache(data, for: path) }
    func removeCachedAvatar(for path: String) async { await base.removeCachedAvatar(for: path) }
    func transitionAvatarSession(to userID: String?) async { await base.transitionAvatarSession(to: userID) }
    func avatarSessionToken() async -> UInt64? { await base.avatarSessionToken() }
    func observeAvatarProfile(_ profile: UserPublicProfile, previous: UserPublicProfile?, token: UInt64?) async -> UserPublicProfile? {
        await base.observeAvatarProfile(profile, previous: previous, token: token)
    }
}
