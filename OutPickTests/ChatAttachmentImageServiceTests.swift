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

    @Test func expiredAttachmentRejectsAnExistingMemoryImage() async throws {
        let path = "rooms/room/messages/\(UUID().uuidString)/attachments/a/display"
        let memory = ImageCacheMemoryStore(totalCostLimitBytes: 1024 * 1024)
        let image = try #require(UIImage(systemName: "star"))
        memory.set(image, forKey: "imageCache|\(path)")
        let service = try await makeRetentionService(memory: memory)
        let valid = ChatMediaCacheResource.attachment(
            path: path, generation: "1", mediaExpiresAt: Date().addingTimeInterval(60)
        )
        let expired = ChatMediaCacheResource.attachment(
            path: path, generation: "1", mediaExpiresAt: Date().addingTimeInterval(-1)
        )

        #expect(service.cachedMemoryImageImmediately(for: valid) != nil)
        #expect(service.cachedMemoryImageImmediately(for: expired) == nil)
    }

    @Test func expiredAttachmentRejectsAnExistingDiskImage() async throws {
        let path = "rooms/room/messages/\(UUID().uuidString)/attachments/a/display"
        let memory = ImageCacheMemoryStore(totalCostLimitBytes: 1024 * 1024)
        let disk = ImageCacheDiskStore(folderName: "ChatRetentionDiskTest-\(UUID().uuidString)")
        let pipeline = ImageCachePipeline(
            fetcher: { _, _ in throw TestError.unimplemented }, memory: memory, disk: disk
        )
        let data = try #require(makeImageData())
        try await pipeline.storeImageData(data, path: path)
        await pipeline.flushPendingWrites()
        memory.remove(forKey: "imageCache|\(path)")
        let service = try await makeRetentionService(remote: pipeline)
        let valid = ChatMediaCacheResource.attachment(
            path: path, generation: "1", mediaExpiresAt: Date().addingTimeInterval(60)
        )
        let expired = ChatMediaCacheResource.attachment(
            path: path, generation: "1", mediaExpiresAt: Date().addingTimeInterval(-1)
        )

        #expect(await service.cachedImage(for: valid) != nil)
        #expect(await service.cachedImage(for: expired) == nil)
    }

    @Test func cachedGIFBytesAreUnavailableAfterAttachmentExpiry() async throws {
        let path = "rooms/room/messages/\(UUID().uuidString)/attachments/a/display.gif"
        let gifData = try #require(Data(base64Encoded: "R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs="))
        let repository = FirebaseImageStorageRepositoryFake()
        repository.imageData = gifData
        let service = try await makeRetentionService(repository: repository)
        let valid = ChatMediaCacheResource.attachment(
            path: path, generation: "1", mediaExpiresAt: Date().addingTimeInterval(60)
        )
        let expired = ChatMediaCacheResource.attachment(
            path: path, generation: "1", mediaExpiresAt: Date().addingTimeInterval(-1)
        )

        #expect(try await service.loadImageData(for: valid, maxBytes: 1024) == gifData)
        #expect(try await service.loadImageData(for: valid, maxBytes: 1024) == gifData)
        #expect(repository.imageDataFetchCount == 1)
        do {
            _ = try await service.loadImageData(for: expired, maxBytes: 1024)
            Issue.record("만료된 GIF 캐시 바이트를 반환함")
        } catch {
            #expect((error as? URLError)?.code == .resourceUnavailable)
        }
    }

    @Test func remoteImageCompletingAfterExpiryDoesNotBecomeVisible() async throws {
        let path = "rooms/room/messages/\(UUID().uuidString)/attachments/a/display"
        let delayed = DelayedChatImageFetcher()
        let pipeline = ImageCachePipeline(
            fetcher: { _, _ in try await delayed.fetch() },
            disk: ImageCacheDiskStore(folderName: "ChatRetentionLateTest-\(UUID().uuidString)")
        )
        let service = try await makeRetentionService(remote: pipeline)
        let resource = ChatMediaCacheResource.attachment(
            path: path, generation: "1", mediaExpiresAt: Date().addingTimeInterval(2)
        )
        let task = Task { try await service.loadImage(for: resource, maxBytes: 1024 * 1024) }
        for _ in 0..<200 {
            if await delayed.hasPendingRequest() { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(await delayed.hasPendingRequest())
        try await Task.sleep(nanoseconds: 2_000_000_000)
        await delayed.complete(with: try #require(makeImageData()))

        do {
            _ = try await task.value
            Issue.record("만료 뒤 완료된 원격 이미지를 반환함")
        } catch {
            #expect((error as? URLError)?.code == .resourceUnavailable)
        }
        #expect(service.cachedMemoryImageImmediately(for: resource) == nil)
    }

    private func makeRetentionService(
        remote: ImageCachePipeline? = nil,
        memory: ImageCacheMemoryStore? = nil,
        repository: FirebaseImageStorageRepositoryFake = FirebaseImageStorageRepositoryFake()
    ) async throws -> ChatAttachmentImageService {
        let remote = remote ?? ImageCachePipeline(
            fetcher: { _, _ in throw TestError.unimplemented },
            memory: memory ?? ImageCacheMemoryStore(totalCostLimitBytes: 1024 * 1024),
            disk: ImageCacheDiskStore(folderName: "ChatRetentionRemoteTest-\(UUID().uuidString)")
        )
        let index = ChatMediaExpiryCacheIndex(
            root: FileManager.default.temporaryDirectory.appendingPathComponent("ChatRetentionIndex-\(UUID().uuidString)")
        )
        try await index.completeCacheRecovery()
        return ChatAttachmentImageService(
            imageStorageRepository: repository,
            pipelines: ChatAttachmentImagePipelines(
                remote: remote,
                outgoingPreview: ImageCachePipeline(
                    fetcher: { _, _ in throw TestError.unimplemented },
                    disk: ImageCacheDiskStore(folderName: "ChatRetentionPreviewTest-\(UUID().uuidString)")
                )
            ),
            ownerAccountID: "account-\(UUID().uuidString)",
            expiryIndex: index
        )
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
    var imageData: Data?
    var imageDataFetchCount = 0
    var imageFileFetchCount = 0
    func fetchImageFileFromStorage(image: String, location: ImageLocation, maxBytes: Int, to url: URL) async throws {
        imageFileFetchCount += 1
        throw TestError.unimplemented
    }
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
        imageDataFetchCount += 1
        guard let imageData else { throw TestError.unimplemented }
        return imageData
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

@MainActor
extension ChatAttachmentImageServiceTests {
    @Test func signedPhotoPipelineUsesHTTPAndCacheWithoutStorageSDK() async throws {
        let bytes = try #require(makeImageData())
        let (service, downloads, repository, http, sdk, resource, index, root) = try signedFixture(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: root) }
        try await index.completeCacheRecovery()
        let first = try await service.loadImage(for: resource, maxBytes: 1024 * 1024)
        let second = try await service.loadImage(for: resource, maxBytes: 1024 * 1024)
        #expect(first.size.width > 0 && second.size.width > 0)
        #expect(repository.calls == 1 && http.calls == 1)
        #expect(sdk.imageDataFetchCount == 0 && sdk.imageFileFetchCount == 0)
        await service.removeCachedImage(for: resource)
        downloads.invalidateSession()
    }

    @Test func signedGIFBytesAreCachedWithoutStorageSDK() async throws {
        let bytes = try #require(Data(base64Encoded: "R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs="))
        let (service, downloads, repository, http, sdk, resource, index, root) = try signedFixture(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: root) }
        try await index.completeCacheRecovery()
        #expect(try await service.loadImageData(for: resource, maxBytes: 1024) == bytes)
        #expect(try await service.loadImageData(for: resource, maxBytes: 1024) == bytes)
        #expect(repository.calls == 1 && http.calls == 1)
        #expect(sdk.imageDataFetchCount == 0 && sdk.imageFileFetchCount == 0)
        await service.removeCachedImage(for: resource)
        downloads.invalidateSession()
    }

    @Test func cacheIndexRecoveryDoesNotPermanentlyBlockSignedRetry() async throws {
        let (service, downloads, repository, http, sdk, resource, index, root) = try signedFixture(bytes: #require(makeImageData()))
        defer { try? FileManager.default.removeItem(at: root) }
        // 복구 전 prepare 실패가 삭제 차단으로 번지면 이후 정상 다운로드도 실패한다.
        #expect(await service.cachedImage(for: resource) == nil)
        #expect(repository.calls == 0 && http.calls == 0)
        try await index.completeCacheRecovery()
        let image = try await service.loadImage(for: resource, maxBytes: 1024 * 1024)
        #expect(image.size.width > 0)
        #expect(repository.calls == 1 && sdk.imageFileFetchCount == 0)
        await service.removeCachedImage(for: resource)
        downloads.invalidateSession()
    }

    @Test func signedOriginalTransportAndVideoSavingPreserveBytesAndLease() async throws {
        let bytes = Data([0, 0, 0, 20]) + Data("ftypmp42".utf8) + Data([0, 0, 0, 0]) + Data("mp42".utf8)
        let (_, downloads, repository, http, sdk, cached, _, root) = try signedFixture(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = ChatOriginalResource(path: cached.path, version: "1", mediaExpiresAt: cached.mediaExpiresAt)
        let files = ChatOriginalFileService(accountID: "qa-account", store: ChatOriginalFileStore(root: root.appendingPathComponent("original")),
            transport: FirebaseChatOriginalFileTransport(repository: sdk, signedDownloads: downloads))
        let request = try ChatMediaURLRequest(path: cached.path)
        let resource = try #require(ChatVideoPlaybackResource(roomID: request.roomID, messageID: request.messageID, attachmentID: request.attachmentID,
            path: cached.path, generation: "1", mediaExpiresAt: cached.mediaExpiresAt))
        let resolver = DefaultChatVideoPlaybackResolver(repository: SignedChatVideoPlaybackURLRepository(service: downloads), originalFiles: files)
        let asset = try await resolver.playbackAsset(for: resource)
        #expect(http.calls == 0)
        let lease = try await resolver.acquireFileForSaving(asset)
        #expect(try Data(contentsOf: lease.fileURL) == bytes)
        let hit = try #require(try await files.cachedOriginal(original))
        await hit.release()
        #expect(repository.calls == 1 && http.calls == 1)
        #expect(sdk.imageFileFetchCount == 0)
        #expect(lease.beginPhotoLibrarySubmission())
        files.invalidateSession()
        #expect(lease.isValid)
        await lease.release()
        resolver.invalidateSession()
        downloads.invalidateSession()
    }

    private func signedFixture(bytes: Data) throws -> (ChatAttachmentImageService, ChatMediaSignedDownloadService,
        AttachmentMediaURLSpy, AttachmentMediaHTTPSpy, FirebaseImageStorageRepositoryFake,
        ChatMediaCacheResource, ChatMediaExpiryCacheIndex, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let expiry = Date().addingTimeInterval(600)
        let repository = AttachmentMediaURLSpy(expiry: expiry)
        let http = AttachmentMediaHTTPSpy(bytes: bytes)
        let downloads = ChatMediaSignedDownloadService(repository: repository, http: http)
        let sdk = FirebaseImageStorageRepositoryFake()
        let index = ChatMediaExpiryCacheIndex(root: root.appendingPathComponent("index"))
        let resource = ChatMediaCacheResource.attachment(
            path: "gs://ready/rooms/room/messages/\(UUID().uuidString)/attachments/attachment/display",
            generation: "1", mediaExpiresAt: expiry)
        let service = ChatAttachmentImageService(imageStorageRepository: sdk, ownerAccountID: "qa-account",
            expiryIndex: index, signedDownloads: downloads)
        return (service, downloads, repository, http, sdk, resource, index, root)
    }
}

@MainActor
private final class AttachmentMediaURLSpy: ChatMediaURLRepository {
    let expiry: Date
    var calls = 0
    init(expiry: Date) { self.expiry = expiry }
    func issue(_ request: ChatMediaURLRequest) async throws -> ChatMediaURLTicket {
        calls += 1
        return ChatMediaURLTicket(url: URL(string: "https://synthetic.invalid/media")!,
            urlExpiresAt: Date().addingTimeInterval(60), mediaExpiresAt: expiry, generation: "1")
    }
}

private final class AttachmentMediaHTTPSpy: ChatMediaHTTPDownloading, @unchecked Sendable {
    let bytes: Data
    @MainActor var calls = 0
    init(bytes: Data) { self.bytes = bytes }
    func download(_ url: URL) async throws -> (URL, Int) {
        try await MainActor.run {
            calls += 1
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try bytes.write(to: file)
            return (file, 200)
        }
    }
}

private actor DelayedChatImageFetcher {
    private var pending: CheckedContinuation<Data, Error>?

    func fetch() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
        }
    }

    func hasPendingRequest() -> Bool { pending != nil }

    func complete(with data: Data) {
        pending?.resume(returning: data)
        pending = nil
    }
}

private enum TestError: Error {
    case unimplemented
}
