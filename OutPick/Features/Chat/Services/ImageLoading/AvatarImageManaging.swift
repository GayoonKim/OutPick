//
//  AvatarImageManaging.swift
//  OutPick
//
//  Created by Codex on 3/24/26.
//

import Foundation
import UIKit

protocol AvatarImageManaging {
    @MainActor func cachedAvatarImmediately(for path: String) -> UIImage?
    @MainActor var avatarCachePolicy: AvatarImageCachePolicy { get }
    func resetAvatarFailures(paths: [String]) async
    func cachedAvatar(_ request: AvatarImageRequest) async -> UIImage?
    func loadAvatar(_ request: AvatarImageRequest) async throws -> UIImage
    func loadOriginalAvatar(for path: String) async throws -> UIImage
    func transitionAvatarSession(to userID: String?) async
    func avatarSessionToken() async -> UInt64?
    func observeAvatarProfile(_ profile: UserPublicProfile, previous: UserPublicProfile?, token: UInt64?) async -> UserPublicProfile?
    func cachedAvatar(for path: String) async -> UIImage?
    func loadAvatar(for path: String, maxBytes: Int) async throws -> UIImage
    func prefetchAvatars(paths: [String], maxBytes: Int, maxConcurrent: Int) async
    func storeAvatarDataToCache(_ data: Data, for path: String) async throws
    func removeCachedAvatar(for path: String) async
}

extension AvatarImageManaging {
    @MainActor func cachedAvatarImmediately(for path: String) -> UIImage? { nil }
    @MainActor var avatarCachePolicy: AvatarImageCachePolicy { .memoryOnly }
    func resetAvatarFailures(paths: [String]) async {}
    // Preview/fake와 기존 호출 호환. 실제 서비스는 아래 정책 API를 구현한다.
    func cachedAvatar(_ request: AvatarImageRequest) async -> UIImage? {
        guard request.representation == .thumbnail else { return nil }
        return await cachedAvatar(for: request.path)
    }
    func loadAvatar(_ request: AvatarImageRequest) async throws -> UIImage {
        try await loadAvatar(for: request.path, maxBytes: request.maximumBytes)
    }
    func loadOriginalAvatar(for path: String) async throws -> UIImage {
        try await loadAvatar(AvatarImageRequest(path: path, representation: .original, cachePolicy: .memoryOnly))
    }
    func transitionAvatarSession(to userID: String?) async { }
    func avatarSessionToken() async -> UInt64? { 0 }
    func observeAvatarProfile(_ profile: UserPublicProfile, previous: UserPublicProfile?, token: UInt64?) async -> UserPublicProfile? { profile }

    func scoped(to policy: @escaping @MainActor () -> AvatarImageCachePolicy) -> AvatarImageManaging {
        ScopedAvatarImageManager(base: self, policy: policy)
    }
}
