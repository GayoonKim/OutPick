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

    @Test func outgoingPreviewStoreCanBeReadBackByKey() async throws {
        let service = makeService()
        let imageData = try #require(makeImageData())
        let key = "preview-\(UUID().uuidString)"

        await service.storeOutgoingPreview(data: imageData, forKey: key)
        let image = await service.cachedOutgoingPreview(forKey: key)

        #expect(image?.size.width ?? 0 > 0)
        #expect(image?.size.height ?? 0 > 0)
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

    private func makeImageData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }.pngData()
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
