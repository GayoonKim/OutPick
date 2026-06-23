//
//  ChatVideoAssetServiceTests.swift
//  OutPickTests
//
//  Created by Codex on 6/23/26.
//

import Testing
import UIKit
@testable import OutPick

struct ChatVideoAssetServiceTests {
    @Test func cacheVideoAssetsLoadsThumbnailAndWarmsStorageURL() async {
        let imageLoader = ChatAttachmentImageLoaderSpy()
        let resolver = ChatStorageURLResolverSpy()
        let service = ChatVideoAssetService(
            attachmentImageLoader: imageLoader,
            storageURLResolver: resolver
        )
        let message = makeMessage(
            id: "message-1",
            thumbPath: "rooms/room-1/messages/message-1/thumb.jpg",
            originalPath: "rooms/room-1/messages/message-1/video.mp4"
        )

        await service.cacheVideoAssetsIfNeeded(for: message, maxThumbnailBytes: 12)

        #expect(imageLoader.loadCalls == [
            .init(path: "rooms/room-1/messages/message-1/thumb.jpg", maxBytes: 12)
        ])
        #expect(resolver.paths == [
            "rooms/room-1/messages/message-1/video.mp4"
        ])
    }

    @Test func cacheVideoAssetsDoesNotResolveLocalOrHTTPVideoPaths() async {
        let imageLoader = ChatAttachmentImageLoaderSpy()
        let resolver = ChatStorageURLResolverSpy()
        let service = ChatVideoAssetService(
            attachmentImageLoader: imageLoader,
            storageURLResolver: resolver
        )

        await service.cacheVideoAssetsIfNeeded(
            for: makeMessage(id: "local", thumbPath: "thumb.jpg", originalPath: "/tmp/video.mp4"),
            maxThumbnailBytes: 12
        )
        await service.cacheVideoAssetsIfNeeded(
            for: makeMessage(id: "http", thumbPath: "thumb-2.jpg", originalPath: "https://example.com/video.mp4"),
            maxThumbnailBytes: 12
        )

        #expect(resolver.paths.isEmpty)
    }

    @Test func cacheVideoAssetsSkipsDuplicateMessageIDs() async {
        let imageLoader = ChatAttachmentImageLoaderSpy()
        let resolver = ChatStorageURLResolverSpy()
        let service = ChatVideoAssetService(
            attachmentImageLoader: imageLoader,
            storageURLResolver: resolver
        )
        let message = makeMessage(
            id: "duplicate",
            thumbPath: "thumb.jpg",
            originalPath: "video.mp4"
        )

        await service.cacheVideoAssetsIfNeeded(for: message, maxThumbnailBytes: 12)
        await service.cacheVideoAssetsIfNeeded(for: message, maxThumbnailBytes: 12)

        #expect(imageLoader.loadCalls.count == 1)
        #expect(resolver.paths.count == 1)
    }

    private func makeMessage(
        id: String,
        thumbPath: String,
        originalPath: String
    ) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: 1,
            roomID: "room-1",
            senderID: "me@example.com",
            senderNickname: "나",
            senderAvatarPath: nil,
            msg: "",
            sentAt: Date(timeIntervalSince1970: 123),
            attachments: [
                Attachment(
                    type: .video,
                    index: 0,
                    pathThumb: thumbPath,
                    pathOriginal: originalPath,
                    width: 100,
                    height: 100,
                    bytesOriginal: 100,
                    hash: id,
                    duration: 1
                )
            ],
            replyPreview: nil
        )
    }
}

private final class ChatAttachmentImageLoaderSpy: ChatAttachmentImageLoading {
    struct LoadCall: Equatable {
        let path: String
        let maxBytes: Int
    }

    private(set) var loadCalls: [LoadCall] = []

    func cacheImagesIfNeeded(for message: ChatMessage, maxBytes: Int) async -> [UIImage] {
        []
    }

    func cachedImage(for path: String) async -> UIImage? {
        nil
    }

    func loadImage(for path: String, maxBytes: Int) async throws -> UIImage {
        loadCalls.append(LoadCall(path: path, maxBytes: maxBytes))
        return UIImage()
    }

    func prefetchThumbnails(for messages: [ChatMessage], maxBytes: Int, maxConcurrent: Int) async {}
    func prefetchImages(paths: [String], maxBytes: Int, maxConcurrent: Int) async {}
    func storeOutgoingPreview(data: Data, forKey key: String) async {}
    func cachedOutgoingPreview(forKey key: String) async -> UIImage? { nil }
}

private final class ChatStorageURLResolverSpy: ChatStorageURLResolving {
    private(set) var paths: [String] = []

    func url(for path: String) async throws -> URL {
        paths.append(path)
        return URL(string: "https://example.com/\(path)")!
    }
}
