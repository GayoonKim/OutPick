//
//  ChatVideoAssetService.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import Foundation

final class ChatVideoAssetService: ChatVideoAssetLoading {
    private let attachmentImageLoader: ChatAttachmentImageLoading
    private let storageURLResolver: ChatStorageURLResolving
    private let preparedRegistry: ChatVideoAssetPreparedRegistry

    init(
        attachmentImageLoader: ChatAttachmentImageLoading,
        storageURLResolver: ChatStorageURLResolving,
        preparedRegistry: ChatVideoAssetPreparedRegistry = ChatVideoAssetPreparedRegistry()
    ) {
        self.attachmentImageLoader = attachmentImageLoader
        self.storageURLResolver = storageURLResolver
        self.preparedRegistry = preparedRegistry
    }

    func cacheVideoAssetsIfNeeded(
        for message: ChatMessage,
        maxThumbnailBytes: Int
    ) async {
        let videoAttachments = message.displayableVideoAttachments
        guard !videoAttachments.isEmpty else { return }
        guard await preparedRegistry.markStartedIfNeeded(messageID: message.ID) else { return }

        for attachment in videoAttachments {
            let thumbPath = attachment.pathThumb
            if !thumbPath.isEmpty {
                _ = try? await attachmentImageLoader.loadImage(
                    for: thumbPath,
                    maxBytes: maxThumbnailBytes
                )
            }

            let originalPath = attachment.pathOriginal
            if isStoragePath(originalPath) {
                _ = try? await storageURLResolver.url(for: originalPath)
            }
        }
    }

    func prefetchVideoAssets(
        for messages: [ChatMessage],
        maxThumbnailBytes: Int,
        maxConcurrent: Int
    ) async {
        let videoMessages = messages.filter { $0.hasDisplayableVideos }
        guard !videoMessages.isEmpty else { return }

        var index = 0
        let concurrency = max(1, maxConcurrent)

        while index < videoMessages.count {
            let end = min(index + concurrency, videoMessages.count)
            let slice = Array(videoMessages[index..<end])

            await withTaskGroup(of: Void.self) { group in
                for message in slice {
                    group.addTask { [weak self] in
                        await self?.cacheVideoAssetsIfNeeded(
                            for: message,
                            maxThumbnailBytes: maxThumbnailBytes
                        )
                    }
                }
                await group.waitForAll()
            }

            index = end
        }
    }

    private func isStoragePath(_ path: String) -> Bool {
        !path.isEmpty && !path.isLocalFilePath
    }
}

actor ChatVideoAssetPreparedRegistry {
    private var preparedMessageIDs: Set<String> = []

    func markStartedIfNeeded(messageID: String) -> Bool {
        guard !preparedMessageIDs.contains(messageID) else { return false }
        preparedMessageIDs.insert(messageID)
        return true
    }
}

private extension String {
    var isLocalFilePath: Bool {
        hasPrefix("/") || hasPrefix("file://") || hasHTTPURLScheme
    }

    var hasHTTPURLScheme: Bool {
        guard let scheme = URL(string: self)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
