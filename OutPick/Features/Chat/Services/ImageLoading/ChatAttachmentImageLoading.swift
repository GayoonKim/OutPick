//
//  ChatAttachmentImageLoading.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import UIKit

protocol ChatAttachmentImageLoading {
    var canPrepareDiskImage: Bool { get }
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
    func prepareDiskImage(for path: String) async {}
    func cachedMemoryImageImmediately(for path: String) -> UIImage? { nil }
    func loadImageData(for path: String, maxBytes: Int) async throws -> Data {
        throw URLError(.unsupportedURL)
    }

    func removeCachedImage(for path: String) async {}
    func preserveLocalPreview(from localPath: String, for remotePath: String) async {}
}
