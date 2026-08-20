//
//  ChatAttachmentImageServiceTests.swift
//  OutPickTests
//
//  Created by Codex on 6/23/26.
//

import Testing
import UIKit
@testable import OutPick

struct ChatAttachmentImageServiceTests {
    @Test func loadImageReturnsLocalFileImageWithoutRemoteFetch() async throws {
        let service = makeService()
        let imageData = try #require(makeImageData())
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentImageServiceTests-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try imageData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let image = try await service.loadImage(
            for: fileURL.absoluteString,
            maxBytes: 1024
        )

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func loadImageDownsamplesLargeLocalUploadSourceForChatRendering() async throws {
        let service = makeService()
        let imageData = try #require(makeImageData(size: CGSize(width: 2_400, height: 1_600)))
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentImageServiceTests-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        try imageData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let image = try await service.loadImage(for: fileURL.absoluteString, maxBytes: 20 * 1024 * 1024)

        #expect(max(image.size.width, image.size.height) <= 1_024)
        #expect(max(image.size.width, image.size.height) >= 1_000)
    }

    @Test func outgoingPreviewStoreCanBeReadBackByKey() async throws {
        let service = makeService()
        let imageData = try #require(makeImageData())
        let key = "preview-\(UUID().uuidString)"

        await service.storeOutgoingPreview(data: imageData, forKey: key)
        let image = await service.cachedOutgoingPreview(forKey: key)

        #expect(image?.size.width ?? 0 > 0)
        #expect(image?.size.height ?? 0 > 0)
    }

    @Test func attachmentResourcePathPreservesReadyBucket() {
        let attachment = Attachment(
            type: .image,
            index: 0,
            bucketThumb: "outpick-test-chat-media",
            bucketOriginal: "outpick-test-chat-media",
            pathThumb: "rooms/room/messages/message/attachments/a/thumbnail",
            pathOriginal: "rooms/room/messages/message/attachments/a/display",
            width: 10,
            height: 10,
            bytesOriginal: 100,
            hash: "hash"
        )

        #expect(attachment.thumbResourcePath ==
            "gs://outpick-test-chat-media/rooms/room/messages/message/attachments/a/thumbnail")
        #expect(attachment.originalResourcePath ==
            "gs://outpick-test-chat-media/rooms/room/messages/message/attachments/a/display")
    }

    private func makeService() -> ChatAttachmentImageService {
        ChatAttachmentImageService(
            imageStorageRepository: FirebaseImageStorageRepositoryFake(),
            pipelines: ChatAttachmentImagePipelines(
                remote: ImageCachePipeline(
                    fetcher: { _, _ in throw TestError.unimplemented },
                    disk: ImageCacheDiskStore(folderName: "ChatAttachmentImageServiceTestsRemote-\(UUID().uuidString)")
                ),
                outgoingPreview: ImageCachePipeline(
                    fetcher: { _, _ in throw TestError.unimplemented },
                    memory: ImageCacheMemoryStore(totalCostLimitBytes: 1024 * 1024),
                    disk: ImageCacheDiskStore(folderName: "ChatAttachmentImageServiceTestsPreview-\(UUID().uuidString)")
                )
            )
        )
    }

    private func makeImageData(size: CGSize = CGSize(width: 1, height: 1)) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.92)
    }
}

private final class FirebaseImageStorageRepositoryFake: FirebaseImageStorageRepositoryProtocol {
    func uploadImage(
        sha: String,
        uid: String,
        type: ImageLocation,
        thumbData: Data,
        originalFileURL: URL,
        contentType: String
    ) async throws -> (avatarThumbPath: String, avatarPath: String) {
        throw TestError.unimplemented
    }

    func uploadPairsToRoomMessage(
        _ pairs: [ProcessedImage],
        roomID: String,
        messageID: String,
        cacheTTLThumbDays: Int,
        cacheTTLOriginalDays: Int,
        cleanupTemp: Bool,
        onProgress: ((Double) -> Void)?
    ) async throws -> [OutPick.Attachment] {
        throw TestError.unimplemented
    }

    func fetchImageDataFromStorage(image: String, location: ImageLocation, maxBytes: Int) async throws -> Data {
        throw TestError.unimplemented
    }

    func fetchImageFromStorage(image: String, location: ImageLocation) async throws -> UIImage {
        throw TestError.unimplemented
    }

    func fetchImagesFromStorage(from imagePaths: [String], location: ImageLocation, createdDate: Date) async throws -> [UIImage] {
        throw TestError.unimplemented
    }

    func prefetchImages(paths: [String], location: ImageLocation, createdDate: Date) {}
    func deleteImageFromStorage(path: String) {}
    func setDataFallbackLimitMB(_ mb: Int) {}
}

private enum TestError: Error {
    case unimplemented
}
