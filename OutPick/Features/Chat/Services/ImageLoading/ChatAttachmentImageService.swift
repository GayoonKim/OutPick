//
//  ChatAttachmentImageService.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import Foundation
import ImageIO
import UIKit

struct ChatAttachmentImagePipelines {
    let remote: ImageCachePipeline
    let outgoingPreview: ImageCachePipeline
}

final class ChatAttachmentImageService: ChatAttachmentImageLoading {
    static let shared = ChatAttachmentImageService(
        imageStorageRepository: FirebaseRepositoryProvider.shared.imageStorageRepository
    )

    private static let sharedPipelines = makePipelines(
        imageStorageRepository: FirebaseRepositoryProvider.shared.imageStorageRepository
    )
    // 계정별 fetcher가 같은 디렉터리를 사용하므로 삭제 revision과 용량은 한 actor가 소유한다.
    private static let sharedRemoteDisk = ImageCacheDiskStore(
        folderName: "ChatImageCacheRetentionV1", maxSizeBytes: 1024 * 1024 * 1024,
        trimTargetBytes: 900 * 1024 * 1024
    )

    private let pipelines: ChatAttachmentImagePipelines
    private let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    private let ownerAccountID: String
    private let expiryIndex: ChatMediaExpiryCacheIndex
    private let signedDownloads: ChatMediaSignedDownloadService?
    private final class PipelineReference {
        weak var value: ImageCachePipeline?
        init(_ value: ImageCachePipeline) { self.value = value }
    }
    private static let pipelineLock = NSLock()
    private static var activePipelines: [PipelineReference] = []
    private static func track(_ pipeline: ImageCachePipeline) {
        pipelineLock.lock(); defer { pipelineLock.unlock() }
        activePipelines.removeAll { $0.value == nil }
        activePipelines.append(PipelineReference(pipeline))
    }
    private static func currentPipelines() -> [ImageCachePipeline] {
        pipelineLock.lock(); defer { pipelineLock.unlock() }
        return [sharedPipelines.remote] + activePipelines.compactMap(\.value)
    }
    private static let imageDataCache = NSCache<NSString, NSData>()
    private static let imageDataPathLock = NSLock()
    private static var imageDataPathsByIdentity: [String: Set<String>] = [:]

    init(
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        pipelines: ChatAttachmentImagePipelines? = nil,
        ownerAccountID: String = "",
        expiryIndex: ChatMediaExpiryCacheIndex = .shared,
        signedDownloads: ChatMediaSignedDownloadService? = nil
    ) {
        self.imageStorageRepository = imageStorageRepository
        self.ownerAccountID = ownerAccountID
        self.expiryIndex = expiryIndex
        self.signedDownloads = signedDownloads
        if let pipelines {
            self.pipelines = pipelines
        } else if let signedDownloads {
            self.pipelines = Self.makePipelines(imageStorageRepository: imageStorageRepository, signedDownloads: signedDownloads)
        } else if imageStorageRepository is FirebaseImageStorageRepository {
            self.pipelines = Self.sharedPipelines
        } else {
            self.pipelines = Self.makePipelines(imageStorageRepository: imageStorageRepository)
        }
        Self.imageDataCache.totalCostLimit = 45 * 1024 * 1024
        Self.track(self.pipelines.remote)
    }

    func cachedMemoryImageImmediately(for resource: ChatMediaCacheResource) -> UIImage? {
        guard resource.isAvailable(at: Date()) else {
            invalidateExpiredResource(resource)
            return nil
        }
        guard !resource.path.isEmpty, isStoragePath(resource.path) else {
            return resource.isLocalFile ? loadLocalImage(from: resource.path) : nil
        }
        return pipelines.remote.cachedMemoryImageImmediately(path: resource.path)
    }

    func prepareDiskImage(for resource: ChatMediaCacheResource) async {
        do {
            try await prepare(resource)
            guard isStoragePath(resource.path) else { return }
            await pipelines.remote.prepareDiskImage(path: resource.path)
        } catch {
            if !resource.isAvailable(at: Date()) { await invalidate(resource) }
        }
    }

    func cachedImage(for resource: ChatMediaCacheResource) async -> UIImage? {
        do {
            try await prepare(resource)
        } catch {
            // 일시적인 인덱스 준비 실패는 삭제된 리소스로 영구 차단하지 않는다.
            if !resource.isAvailable(at: Date()) { await invalidate(resource) }
            return nil
        }
        if let local = loadLocalImage(from: resource.path) { return local }
        guard isStoragePath(resource.path) else { return nil }
        let image = await pipelines.remote.cachedImage(path: resource.path)
        guard resource.isAvailable(at: Date()) else {
            await invalidate(resource)
            return nil
        }
        return image
    }

    func loadImage(for resource: ChatMediaCacheResource, maxBytes: Int) async throws -> UIImage {
        try await loadImage(for: resource, maxBytes: maxBytes, priority: .visible)
    }

    func loadImage(for resource: ChatMediaCacheResource, maxBytes: Int, priority: ImageRequestPriority) async throws -> UIImage {
        try await prepare(resource)
        if let local = loadLocalImage(from: resource.path) { return local }
        guard isStoragePath(resource.path) else { throw URLError(.badURL) }
        do {
            let image = try await pipelines.remote.loadImage(
                path: resource.path,
                maxBytes: maxBytes,
                storePolicy: .memoryAndDisk,
                priority: priority
            )
            guard resource.isAvailable(at: Date()) else {
                await invalidate(resource)
                throw URLError(.resourceUnavailable)
            }
            return image
        } catch {
            if !resource.isAvailable(at: Date()) { await invalidate(resource) }
            throw error
        }
    }

    func loadImageData(for resource: ChatMediaCacheResource, maxBytes: Int) async throws -> Data {
        try await prepare(resource)
        if let fileURL = resource.path.localFileURL {
            return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }
        let cacheKey = resource.path as NSString
        if let cached = Self.imageDataCache.object(forKey: cacheKey) {
            let data = cached as Data
            guard data.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
            guard resource.isAvailable(at: Date()) else {
                await invalidate(resource)
                throw URLError(.resourceUnavailable)
            }
            return data
        }
        guard isStoragePath(resource.path) else { throw URLError(.badURL) }
        let data = try await fetchData(path: resource.path, maxBytes: maxBytes)
        guard resource.isAvailable(at: Date()) else {
            await invalidate(resource)
            throw URLError(.resourceUnavailable)
        }
        Self.imageDataCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
        Self.rememberImageDataPath(resource.path)
        return data
    }

    func removeCachedImage(for resource: ChatMediaCacheResource) async {
        await invalidate(resource)
    }

    func preserveLocalPreview(from localPath: String, for resource: ChatMediaCacheResource) async {
        guard resource.isAvailable(at: Date()) else { await invalidate(resource); return }
        do { try await prepare(resource) } catch { return }
        let metric = ImageCacheMetrics.shared.begin("chatPreview.preserveLocal", key: resource.path)
        var outcome = "preparationFailed"
        defer { ImageCacheMetrics.shared.end(metric, outcome: outcome) }
        guard let local = loadLocalImage(from: localPath),
              let data = local.jpegData(compressionQuality: 0.7) else { return }
        do {
            try await pipelines.remote.storeImageData(data, path: resource.path)
            if !resource.isAvailable(at: Date()) { await invalidate(resource); return }
            outcome = "returned"
        } catch { outcome = Task.isCancelled || error is CancellationError ? "cancelled" : "failed" }
    }

    static func removeExpiredCacheEntries(at now: Date) async {
        let index = ChatMediaExpiryCacheIndex.shared
        if await index.requiresCacheRecovery() {
            // 새 만료 전용 cache의 색인을 잃으면 해당 namespace만 비운다. 구형 개발 cache는 건드리지 않는다.
            for pipeline in currentPipelines() { await pipeline.removeAllCachedImages() }
            resetImageDataPaths()
            imageDataCache.removeAllObjects()
            _ = await ChatOriginalFileStore.shared.removeExpired(at: now)
            try? await index.completeCacheRecovery()
            return
        }
        let entries = await index.expiredEntries(at: now)
        guard !entries.isEmpty else {
            _ = await ChatOriginalFileStore.shared.removeExpired(at: now)
            return
        }
        let identities = Set(entries.map(\.imageCacheIdentity))
        var imageRemovalSucceeded = true
        for pipeline in currentPipelines() {
            let removed = await pipeline.removeExpiredCacheIdentities(identities)
            imageRemovalSucceeded = removed && imageRemovalSucceeded
        }
        for identity in identities { removeImageData(forCacheIdentity: identity) }
        let originalsRemoved = await ChatOriginalFileStore.shared.removeExpired(at: now)
        guard imageRemovalSucceeded, originalsRemoved else { return }
        try? await index.removeEntries(ids: Set(entries.map(\.id)))
    }

    func pruneExpiredCacheEntries(at now: Date) async {
        await Self.removeExpiredCacheEntries(at: now)
    }

    private func prepare(_ resource: ChatMediaCacheResource) async throws {
        guard resource.isAvailable(at: Date()) else { throw URLError(.resourceUnavailable) }
        guard case .attachment = resource.scope else { return }
        try await expiryIndex.register(resource: resource, accountID: ownerAccountID)
        if let values = resource.expiryIndexValues {
            await signedDownloads?.register(ChatOriginalResource(path: resource.path, version: values.generation,
                mediaExpiresAt: values.mediaExpiresAt))
        }
        Self.rememberImageDataPath(resource.path)
    }

    private func invalidateExpiredResource(_ resource: ChatMediaCacheResource) {
        Self.removeImageData(path: resource.path)
        Task { await invalidate(resource) }
    }

    private func invalidate(_ resource: ChatMediaCacheResource) async {
        await signedDownloads?.remove(path: resource.path)
        Self.removeImageData(path: resource.path)
        if isStoragePath(resource.path) {
            await pipelines.remote.removeImage(path: resource.path)
        }
        if case .attachment = resource.scope {
            _ = await ChatOriginalFileStore.shared.removeExpired(at: Date())
        }
    }

    private static func resetImageDataPaths() {
        imageDataPathLock.lock()
        defer { imageDataPathLock.unlock() }
        imageDataPathsByIdentity.removeAll()
    }

    private static func rememberImageDataPath(_ path: String) {
        let identity = "imageCache|\(path)".sha256()
        imageDataPathLock.lock()
        imageDataPathsByIdentity[identity, default: []].insert(path)
        imageDataPathLock.unlock()
    }

    private static func removeImageData(path: String) {
        guard !path.isEmpty else { return }
        imageDataCache.removeObject(forKey: path as NSString)
    }

    private static func removeImageData(forCacheIdentity identity: String) {
        imageDataPathLock.lock()
        let paths = imageDataPathsByIdentity[identity] ?? []
        imageDataPathLock.unlock()
        for path in paths { imageDataCache.removeObject(forKey: path as NSString) }
    }

    func cachedMemoryImageImmediately(for path: String) -> UIImage? {
        // 원격 경로의 동기 조회는 만료 레코드를 확인할 수 없어 안전하게 거부한다.
        guard isStoragePath(path) else { return nil }
        return nil
    }

    var canPrepareDiskImage: Bool { pipelines.remote.canPrepareDiskImage }

    func prepareDiskImage(for path: String) async {
        guard isStoragePath(path), await expiryIndex.isAvailable(path: path, at: Date()) else { return }
        await pipelines.remote.prepareDiskImage(path: path)
    }

    func cachedImage(for path: String) async -> UIImage? {
        guard !path.isEmpty else { return nil }

        if let local = loadLocalImage(from: path) {
            return local
        }

        guard isStoragePath(path), await expiryIndex.isAvailable(path: path, at: Date()) else { return nil }
        let image = await pipelines.remote.cachedImage(path: path)
        guard await expiryIndex.isAvailable(path: path, at: Date()) else {
            await pipelines.remote.removeImage(path: path)
            return nil
        }
        return image
    }

    func loadImage(for path: String, maxBytes: Int) async throws -> UIImage {
        try await loadImage(for: path, maxBytes: maxBytes, priority: .visible)
    }

    func loadImage(for path: String, maxBytes: Int, priority: ImageRequestPriority) async throws -> UIImage {
        if let local = loadLocalImage(from: path) {
            return local
        }

        guard isStoragePath(path), await expiryIndex.isAvailable(path: path, at: Date()) else {
            throw URLError(.resourceUnavailable)
        }

        let image = try await pipelines.remote.loadImage(path: path, maxBytes: maxBytes, storePolicy: .memoryAndDisk, priority: priority)
        guard await expiryIndex.isAvailable(path: path, at: Date()) else {
            await pipelines.remote.removeImage(path: path)
            throw URLError(.resourceUnavailable)
        }
        return image
    }

    func loadImageData(for path: String, maxBytes: Int) async throws -> Data {
        guard !path.isEmpty else { throw URLError(.badURL) }

        if let fileURL = path.localFileURL {
            return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }

        guard isStoragePath(path), await expiryIndex.isAvailable(path: path, at: Date()) else {
            throw URLError(.resourceUnavailable)
        }
        let cacheKey = path as NSString
        if let cached = Self.imageDataCache.object(forKey: cacheKey) {
            let data = cached as Data
            guard data.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
            guard await expiryIndex.isAvailable(path: path, at: Date()) else { throw URLError(.resourceUnavailable) }
            return data
        }

        let data = try await fetchData(path: path, maxBytes: maxBytes)
        guard await expiryIndex.isAvailable(path: path, at: Date()) else { throw URLError(.resourceUnavailable) }
        Self.imageDataCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
        Self.rememberImageDataPath(path)
        return data
    }

    func prefetchImages(paths: [String], maxBytes: Int, maxConcurrent: Int) async {
        var normalized: [String] = []
        for path in Set(paths.filter { isStoragePath($0) }) {
            guard await expiryIndex.isAvailable(path: path, at: Date()) else { continue }
            normalized.append(path)
        }
        guard !normalized.isEmpty else { return }
        let items = normalized.map { (path: $0, maxBytes: maxBytes) }
        await pipelines.remote.prefetch(items: items, concurrency: maxConcurrent)
    }

    func storeOutgoingPreview(data: Data, forKey key: String) async {
        try? await pipelines.outgoingPreview.storeImageData(data, path: outgoingPreviewKey(for: key))
    }

    func cachedOutgoingPreview(forKey key: String) async -> UIImage? {
        await pipelines.outgoingPreview.cachedImage(path: outgoingPreviewKey(for: key))
    }

    func preserveLocalPreview(from localPath: String, for remotePath: String) async {
        guard await expiryIndex.isAvailable(path: remotePath, at: Date()) else { return }
        let metric = ImageCacheMetrics.shared.begin("chatPreview.preserveLocal", key: remotePath)
        var outcome = "preparationFailed"
        defer { ImageCacheMetrics.shared.end(metric, outcome: outcome) }
        guard let local = loadLocalImage(from: localPath),
              let data = local.jpegData(compressionQuality: 0.7) else { return }
        // 서버 파일은 수정하지 않는다. 정상 버블의 작은 로컬 cache만 먼저 연결한다.
        do {
            try await pipelines.remote.storeImageData(data, path: remotePath)
            guard await expiryIndex.isAvailable(path: remotePath, at: Date()) else {
                await pipelines.remote.removeImage(path: remotePath)
                return
            }
            // 실제 쓰기 결과는 diskWrite.total로 구분한다. 이 반환은 저장 성공 보장이 아니다.
            outcome = "returned"
        } catch { outcome = Task.isCancelled || error is CancellationError ? "cancelled" : "failed" }
    }

    private static func decodePreview(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func decodePreview(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    func removeCachedImage(for path: String) async {
        await signedDownloads?.remove(path: path)
        Self.removeImageData(path: path)
        await pipelines.remote.removeImage(path: path)
    }

    private func isStoragePath(_ path: String) -> Bool {
        !path.isEmpty && !path.isLocalFilePath
    }

    private func loadLocalImage(from path: String) -> UIImage? {
        guard let fileURL = path.localFileURL else { return nil }
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private func outgoingPreviewKey(for key: String) -> String {
        "chatThumb|\(key)"
    }

    private static func makePipelines(
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        signedDownloads: ChatMediaSignedDownloadService? = nil
    ) -> ChatAttachmentImagePipelines {
        ChatAttachmentImagePipelines(
            remote: ImageCachePipeline(
                fetcher: { path, maxBytes in
                    if let signedDownloads { return try await signedDownloads.data(path: path, maxBytes: maxBytes) }
                    return try await imageStorageRepository.fetchImageDataFromStorage(
                        image: path,
                        location: .roomImage,
                        maxBytes: maxBytes
                    )
                },
                fileFetcher: { path, maxBytes, url in
                    if let signedDownloads { try await signedDownloads.file(path: path, maxBytes: maxBytes, to: url); return }
                    try await imageStorageRepository.fetchImageFileFromStorage(image: path, location: .roomImage, maxBytes: maxBytes, to: url)
                },
                memory: ImageCacheMemoryStore(totalCostLimitBytes: 1024 * 1024 * 1024, usesLRU: true),
                disk: sharedRemoteDisk,
                usesDirectDiskFileDecoding: true,
                bypassDirectDiskLimits: true,
                decoder: { decodePreview($0) },
                fileDecoder: { decodePreview($0) }
            ),
            outgoingPreview: ImageCachePipeline(
                fetcher: { _, _ in throw URLError(.fileDoesNotExist) },
                memory: ImageCacheMemoryStore(totalCostLimitBytes: 80 * 1024 * 1024),
                disk: ImageCacheDiskStore(folderName: "ThumbCache"),
                decoder: { decodePreview($0) },
                fileDecoder: { decodePreview($0) }
            )
        )
    }

    private func fetchData(path: String, maxBytes: Int) async throws -> Data {
        if let signedDownloads { return try await signedDownloads.data(path: path, maxBytes: maxBytes) }
        return try await imageStorageRepository.fetchImageDataFromStorage(image: path, location: .roomImage, maxBytes: maxBytes)
    }
}

private extension String {
    var isLocalFilePath: Bool {
        hasPrefix("/") || hasPrefix("file://")
    }

    var localFileURL: URL? {
        if hasPrefix("file://") {
            return URL(string: self)
        }
        if hasPrefix("/") {
            return URL(fileURLWithPath: self)
        }
        return nil
    }
}
