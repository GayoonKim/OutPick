import Foundation
import UIKit
import FirebaseStorage

final class AvatarImageService: AvatarImageManaging {
    @MainActor func cachedAvatarImmediately(for path: String) -> UIImage? {
        guard !path.isEmpty, localURL(path) == nil else { return nil }
        return session.immediateReads.read(path: path) {
            pipeline.cachedMemoryImageImmediately(path: path)
        }
    }
    private let pipeline: ImageCachePipeline
    private let session: AvatarImageSessionController
    private let resources: ImagePipelineResources
    private let originalTimeoutWait: @Sendable () async throws -> Void

    init(imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
         pipeline: ImageCachePipeline? = nil,
         resources: ImagePipelineResources = .shared,
         promotionEncoding: ImageCachePromotionEncoding? = nil,
         requiresSession: Bool = false,
         sessionOwnerDefaults: UserDefaults? = nil,
         originalTimeoutWait: @escaping @Sendable () async throws -> Void = {
             try await Task.sleep(nanoseconds: 30_000_000_000)
         }) {
        self.resources = resources
        self.originalTimeoutWait = originalTimeoutWait
        self.session = AvatarImageSessionController(requiresSession: requiresSession, ownerDefaults: sessionOwnerDefaults)
        self.pipeline = pipeline ?? ImageCachePipeline(
            fetcher: { path, maxBytes in
                try await imageStorageRepository.fetchImageDataFromStorage(image: path, location: .profileImage, maxBytes: maxBytes)
            },
            fileFetcher: { path, maxBytes, url in
                try await imageStorageRepository.fetchImageFileFromStorage(image: path, location: .profileImage, maxBytes: maxBytes, to: url)
            },
            disk: ImageCacheDiskStore(folderName: "AvatarImageCache", resources: resources,
                                     maxSizeBytes: 100 * 1024 * 1024, trimTargetBytes: 75 * 1024 * 1024),
            resources: resources, promotionEncoding: promotionEncoding
        )
    }

    func cachedAvatar(_ request: AvatarImageRequest) async -> UIImage? {
        guard request.representation == .thumbnail else { return nil }
        return try? await session.perform(path: request.path) { [self] in
            if let url = localURL(request.path) { return try await localImage(url) }
            guard !request.path.isEmpty else { return nil }
            return await pipeline.cachedImage(path: request.path, storePolicy: request.storePolicy)
        }
    }

    func loadAvatar(_ request: AvatarImageRequest) async throws -> UIImage {
        let token = await session.token()
        do {
            let image = try await session.perform(path: request.path) { [self] in
                if let url = localURL(request.path) { return try await localImage(url) }
                guard !request.path.isEmpty else { throw URLError(.badURL) }
                return try await loadRemoteAvatar(request)
            }
            guard let image else { throw ImageCachePipelineError.invalidImageData }
            return image
        } catch {
            let ns = error as NSError
            if ns.domain == StorageErrorDomain,
               [StorageErrorCode.objectNotFound.rawValue, StorageErrorCode.unauthorized.rawValue].contains(ns.code) {
                await session.markUnavailable(path: request.path, token: token)
                throw AvatarImageLoadingError.unavailable
            }
            throw error
        }
    }

    private func loadRemoteAvatar(_ request: AvatarImageRequest) async throws -> UIImage {
        let priority = ImageWorkContext.current?.priority ?? .visible
        let load: @Sendable () async throws -> UIImage = { [pipeline] in
            try await pipeline.loadImage(path: request.path, maxBytes: request.maximumBytes,
                                         storePolicy: request.storePolicy, priority: priority)
        }
        guard request.representation == .original else { return try await load() }
        // 소비자 대기만 제한한다. 병합된 다른 소비자는 유지하고 마지막 취소는 SDK 전송까지 전달한다.
        return try await withThrowingTaskGroup(of: UIImage.self) { group in
            group.addTask { try await load() }
            group.addTask { [originalTimeoutWait] in
                try await originalTimeoutWait()
                try Task.checkCancellation()
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let image = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return image
        }
    }

    func cachedAvatar(for path: String) async -> UIImage? {
        await cachedAvatar(AvatarImageRequest(path: path, representation: .thumbnail, cachePolicy: .memoryOnly))
    }
    func loadAvatar(for path: String, maxBytes: Int) async throws -> UIImage {
        try await loadAvatar(AvatarImageRequest(path: path, representation: .thumbnail, cachePolicy: .memoryOnly))
    }
    func prefetchAvatars(paths: [String], maxBytes: Int, maxConcurrent: Int) async {
        await scoped(to: { .memoryOnly }).prefetchAvatars(paths: paths, maxBytes: maxBytes, maxConcurrent: maxConcurrent)
    }
    func storeAvatarDataToCache(_ data: Data, for path: String) async throws {
        _ = try await session.perform(path: path) { [pipeline] in
            try await pipeline.storeImageData(data, path: path)
            return nil
        }
    }
    func removeCachedAvatar(for path: String) async {
        session.immediateReads.beginInvalidation([path])
        defer { session.immediateReads.endInvalidation([path]) }
        await pipeline.removeImage(path: path)
    }
    func transitionAvatarSession(to userID: String?) async {
        await session.transition(to: userID) { [pipeline] in await pipeline.removeAllCachedImages() }
    }
    func avatarSessionToken() async -> UInt64? { await session.token() }
    func resetAvatarFailures(paths: [String]) async { await session.resetFailures(paths: paths) }
    func observeAvatarProfile(_ profile: UserPublicProfile, previous: UserPublicProfile?, token: UInt64?) async -> UserPublicProfile? {
        await session.observe(profile, previous: previous, token: token) { [pipeline] path in
            await pipeline.removeImage(path: path)
        }
    }

    private func localURL(_ path: String) -> URL? {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL { return url }
        return nil
    }
    private func localImage(_ url: URL) async throws -> UIImage {
        try await resources.decode.withPermit { [resources] in
            try await resources.io.withPermit(kind: .read) {
                try Task.checkCancellation()
                guard let image = ImageFileDecoding.image(url) else { throw ImageCachePipelineError.invalidImageData }
                try Task.checkCancellation()
                return image
            }
        }
    }
}
