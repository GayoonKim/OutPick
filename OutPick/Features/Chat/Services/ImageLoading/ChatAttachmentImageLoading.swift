//
//  ChatAttachmentImageLoading.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import UIKit

protocol ChatAttachmentImageLoading {
    func cacheImagesIfNeeded(for message: ChatMessage, maxBytes: Int) async -> [UIImage]
    func cachedImage(for path: String) async -> UIImage?
    func loadImage(for path: String, maxBytes: Int) async throws -> UIImage
    func loadImageData(for path: String, maxBytes: Int) async throws -> Data
    func prefetchThumbnails(for messages: [ChatMessage], maxBytes: Int, maxConcurrent: Int) async
    func prefetchImages(paths: [String], maxBytes: Int, maxConcurrent: Int) async
    func storeOutgoingPreview(data: Data, forKey key: String) async
    func cachedOutgoingPreview(forKey key: String) async -> UIImage?
    func removeCachedImage(for path: String) async
}

extension ChatAttachmentImageLoading {
    func loadImageData(for path: String, maxBytes: Int) async throws -> Data {
        throw URLError(.unsupportedURL)
    }

    func removeCachedImage(for path: String) async {}
}
