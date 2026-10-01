//
//  ChatAttachmentImageLoading.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import UIKit

protocol ChatAttachmentImageLoading {
    var canPrepareDiskImage: Bool { get }
    func prepareDiskImage(for resource: ChatMediaCacheResource) async
    func cachedMemoryImageImmediately(for resource: ChatMediaCacheResource) -> UIImage?
    func cachedImage(for resource: ChatMediaCacheResource) async -> UIImage?
    func loadImage(for resource: ChatMediaCacheResource, maxBytes: Int) async throws -> UIImage
    func loadImage(for resource: ChatMediaCacheResource, maxBytes: Int, priority: ImageRequestPriority) async throws -> UIImage
    func loadImageData(for resource: ChatMediaCacheResource, maxBytes: Int) async throws -> Data
    func removeCachedImage(for resource: ChatMediaCacheResource) async
    func preserveLocalPreview(from localPath: String, for resource: ChatMediaCacheResource) async
    func pruneExpiredCacheEntries(at now: Date) async
    func prepareDiskImage(for path: String) async
    func cachedMemoryImageImmediately(for path: String) -> UIImage?
    func cachedImage(for path: String) async -> UIImage?
    func loadImage(for path: String, maxBytes: Int) async throws -> UIImage
    func loadImage(for path: String, maxBytes: Int, priority: ImageRequestPriority) async throws -> UIImage
    func loadImageData(for path: String, maxBytes: Int) async throws -> Data
    func prefetchImages(paths: [String], maxBytes: Int, maxConcurrent: Int) async
    func storeOutgoingPreview(data: Data, forKey key: String) async
    func cachedOutgoingPreview(forKey key: String) async -> UIImage?
    func removeCachedImage(for path: String) async
    func preserveLocalPreview(from localPath: String, for remotePath: String) async
}

extension ChatAttachmentImageLoading {
    var canPrepareDiskImage: Bool { false }
    func prepareDiskImage(for resource: ChatMediaCacheResource) async { await prepareDiskImage(for: resource.path) }
    func cachedMemoryImageImmediately(for resource: ChatMediaCacheResource) -> UIImage? { cachedMemoryImageImmediately(for: resource.path) }
    func cachedImage(for resource: ChatMediaCacheResource) async -> UIImage? { await cachedImage(for: resource.path) }
    func loadImage(for resource: ChatMediaCacheResource, maxBytes: Int) async throws -> UIImage {
        try await loadImage(for: resource.path, maxBytes: maxBytes)
    }
    func loadImage(for resource: ChatMediaCacheResource, maxBytes: Int, priority: ImageRequestPriority) async throws -> UIImage {
        try await loadImage(for: resource.path, maxBytes: maxBytes, priority: priority)
    }
    func loadImageData(for resource: ChatMediaCacheResource, maxBytes: Int) async throws -> Data {
        try await loadImageData(for: resource.path, maxBytes: maxBytes)
    }
    func removeCachedImage(for resource: ChatMediaCacheResource) async { await removeCachedImage(for: resource.path) }
    func pruneExpiredCacheEntries(at now: Date) async {}
    func preserveLocalPreview(from localPath: String, for resource: ChatMediaCacheResource) async {
        await preserveLocalPreview(from: localPath, for: resource.path)
    }
    func prepareDiskImage(for path: String) async {}
    func cachedMemoryImageImmediately(for path: String) -> UIImage? { nil }
    func loadImageData(for path: String, maxBytes: Int) async throws -> Data {
        throw URLError(.unsupportedURL)
    }

    func removeCachedImage(for path: String) async {}
    func preserveLocalPreview(from localPath: String, for remotePath: String) async {}
}
