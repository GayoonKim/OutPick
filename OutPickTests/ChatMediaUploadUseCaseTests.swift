//
//  ChatMediaUploadUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 6/18/26.
//

import Foundation
import Testing
import UIKit
@testable import OutPick

private typealias ChatAttachment = OutPick.Attachment

struct ChatMediaUploadUseCaseTests {
    @Test func makePendingImageMessageBuildsLocalPreviewAttachments() throws {
        let previewDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatMediaUploadUseCaseTests-\(UUID().uuidString)", isDirectory: true)
        let useCase = makeUseCase(previewDirectory: previewDirectory)
        let first = try makeProcessedImage(index: 2, sha256: "second-sha")
        let second = try makeProcessedImage(index: 1, sha256: "first-sha")

        let message = try #require(useCase.makePendingImageMessage(
            roomID: "room-1",
            messageID: "message-1",
            pairs: [first, second]
        ))

        #expect(message.ID == "message-1")
        #expect(message.roomID == "room-1")
        #expect(message.senderID == "me@example.com")
        #expect(message.senderNickname == "나")
        #expect(message.senderAvatarPath == "avatars/me.jpg")
        #expect(message.attachments.map(\.index) == [1, 2])
        #expect(message.attachments.allSatisfy { $0.type == .image })
        #expect(message.attachments.allSatisfy { $0.pathThumb.hasPrefix("file://") })
        for attachment in message.attachments {
            let url = try #require(URL(string: attachment.pathThumb))
            #expect(FileManager.default.fileExists(atPath: url.path))
        }

        try? FileManager.default.removeItem(at: previewDirectory)
    }

    @Test func makePendingVideoMessageBuildsLocalVideoPreviewAttachment() throws {
        let previewDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatMediaUploadUseCaseTests-\(UUID().uuidString)", isDirectory: true)
        let useCase = makeUseCase(previewDirectory: previewDirectory)
        let prepared = try makePreparedVideo()

        let message = try #require(useCase.makePendingVideoMessage(
            roomID: "room-1",
            messageID: "video-1",
            prepared: prepared
        ))

        let attachment = try #require(message.attachments.first)
        #expect(message.ID == "video-1")
        #expect(message.roomID == "room-1")
        #expect(message.senderID == "me@example.com")
        #expect(attachment.type == .video)
        #expect(attachment.pathThumb.hasPrefix("file://"))
        #expect(attachment.pathOriginal == prepared.compressedFileURL.path)
        #expect(attachment.width == prepared.width)
        #expect(attachment.height == prepared.height)
        #expect(attachment.duration == prepared.duration)
        let thumbURL = try #require(URL(string: attachment.pathThumb))
        #expect(FileManager.default.fileExists(atPath: thumbURL.path))

        try? FileManager.default.removeItem(at: previewDirectory)
    }

    @Test func uploadPendingImagesDeletesOriginalsAndSendDelegatesToRepository() async throws {
        let imageRepository = FirebaseImageStorageRepositoryFake()
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let useCase = makeUseCase(
            imageRepository: imageRepository,
            sendingRepository: sendingRepository
        )
        let pair = try makeProcessedImage(index: 0, sha256: "image-sha")
        let attachment = makeAttachment(hash: "image-sha")
        imageRepository.uploadResult = [attachment]
        var progressValues: [Double] = []

        let attachments = try await useCase.uploadPendingImages(
            pairs: [pair],
            roomID: "room-1",
            messageID: "message-1",
            onProgress: { progressValues.append($0) }
        )
        try await useCase.sendUploadedImages(
            room: makeRoom(id: "room-1"),
            attachments: attachments,
            clientMessageID: "message-1"
        )

        #expect(sendingRepository.preflightCalls == [
            .init(roomID: "room-1", messageID: "message-1", kind: "images")
        ])
        #expect(imageRepository.uploadCalls.count == 1)
        #expect(imageRepository.uploadCalls.first?.roomID == "room-1")
        #expect(imageRepository.uploadCalls.first?.messageID == "message-1")
        #expect(progressValues == [0.25, 1.0])
        #expect(FileManager.default.fileExists(atPath: pair.originalFileURL.path) == false)
        #expect(sendingRepository.imageCalls.count == 1)
        #expect(sendingRepository.imageCalls.first?.attachments == [attachment])
        #expect(sendingRepository.imageCalls.first?.senderAvatarPath == "avatars/me.jpg")
        #expect(sendingRepository.imageCalls.first?.clientMessageID == "message-1")
    }

    @Test func uploadPendingImagesDoesNotUploadWhenPreflightFails() async throws {
        let imageRepository = FirebaseImageStorageRepositoryFake()
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        sendingRepository.preflightError = TestError.unimplemented
        let useCase = makeUseCase(
            imageRepository: imageRepository,
            sendingRepository: sendingRepository
        )
        let pair = try makeProcessedImage(index: 0, sha256: "image-sha")

        do {
            _ = try await useCase.uploadPendingImages(
                pairs: [pair],
                roomID: "room-1",
                messageID: "message-1",
                onProgress: nil
            )
            Issue.record("preflight 실패 시 업로드가 성공하면 안 됩니다.")
        } catch {
            #expect(imageRepository.uploadCalls.isEmpty)
            #expect(FileManager.default.fileExists(atPath: pair.originalFileURL.path))
        }

        try? FileManager.default.removeItem(at: pair.originalFileURL)
    }

    @Test func cacheFailedImageThumbnailsStoresEveryPairThumb() async throws {
        let imageLoader = ChatAttachmentImageLoaderSpy()
        let useCase = makeUseCase(attachmentImageLoader: imageLoader)
        let first = try makeProcessedImage(index: 0, sha256: "first")
        let second = try makeProcessedImage(index: 1, sha256: "second")

        await useCase.cacheFailedImageThumbnails([first, second])

        let keys = await imageLoader.outgoingPreviewKeys()
        #expect(keys == ["first", "second"])
    }

    @Test func uploadVideoUploadsFileAndThumbnailThenSendsPayload() async throws {
        let videoRepository = FirebaseVideoStorageRepositoryFake()
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let imageLoader = ChatAttachmentImageLoaderSpy()
        let useCase = makeUseCase(
            videoRepository: videoRepository,
            sendingRepository: sendingRepository,
            attachmentImageLoader: imageLoader
        )
        let prepared = try makePreparedVideo()
        var progressValues: [Double] = []

        let payload = try await useCase.uploadVideo(
            roomID: "room-1",
            messageID: "video-1",
            prepared: prepared,
            onProgress: { progressValues.append($0) }
        )
        try await useCase.sendUploadedVideo(roomID: "room-1", payload: payload)

        #expect(sendingRepository.preflightCalls == [
            .init(roomID: "room-1", messageID: "video-1", kind: "video")
        ])
        #expect(payload.messageID == "video-1")
        #expect(payload.storagePath == "rooms/room-1/messages/video-1/video/video.mp4")
        #expect(payload.thumbnailPath == "rooms/room-1/messages/video-1/video/thumb.jpg")
        #expect(payload.preset == "standard720")
        #expect(videoRepository.fileUploadCalls.map(\.path) == [payload.storagePath])
        #expect(videoRepository.dataUploadCalls.map(\.path) == [payload.thumbnailPath])
        #expect(progressValues == [0.5, 1.0])
        #expect(await imageLoader.outgoingPreviewKeys() == ["video-sha"])
        #expect(sendingRepository.videoCalls.count == 1)
        #expect(sendingRepository.videoCalls.first?.payload.messageID == "video-1")
        #expect(sendingRepository.videoCalls.first?.senderAvatarPath == "avatars/me.jpg")
    }

    @Test func uploadVideoDoesNotUploadWhenPreflightFails() async throws {
        let videoRepository = FirebaseVideoStorageRepositoryFake()
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        sendingRepository.preflightError = TestError.unimplemented
        let useCase = makeUseCase(
            videoRepository: videoRepository,
            sendingRepository: sendingRepository
        )
        let prepared = try makePreparedVideo()

        do {
            _ = try await useCase.uploadVideo(
                roomID: "room-1",
                messageID: "video-1",
                prepared: prepared,
                onProgress: { _ in }
            )
            Issue.record("preflight 실패 시 비디오 업로드가 성공하면 안 됩니다.")
        } catch {
            #expect(videoRepository.fileUploadCalls.isEmpty)
            #expect(videoRepository.dataUploadCalls.isEmpty)
        }

        try? FileManager.default.removeItem(at: prepared.compressedFileURL)
    }

    @Test func sendFailedVideoDelegatesLocalPreparedVideoToRepository() throws {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let useCase = makeUseCase(sendingRepository: sendingRepository)
        let prepared = try makePreparedVideo()

        useCase.sendFailedVideo(roomID: "room-1", prepared: prepared)

        #expect(sendingRepository.failedVideoCalls.count == 1)
        #expect(sendingRepository.failedVideoCalls.first?.roomID == "room-1")
        #expect(sendingRepository.failedVideoCalls.first?.senderID == "me@example.com")
        #expect(sendingRepository.failedVideoCalls.first?.senderNickname == "나")
        #expect(sendingRepository.failedVideoCalls.first?.localURL == prepared.compressedFileURL)
        #expect(sendingRepository.failedVideoCalls.first?.presetCode == "standard720")
    }

    private func makeUseCase(
        imageRepository: FirebaseImageStorageRepositoryFake = FirebaseImageStorageRepositoryFake(),
        videoRepository: FirebaseVideoStorageRepositoryFake = FirebaseVideoStorageRepositoryFake(),
        sendingRepository: ChatMediaMessageSendingRepositorySpy = ChatMediaMessageSendingRepositorySpy(),
        attachmentImageLoader: ChatAttachmentImageLoading = ChatAttachmentImageLoaderSpy(),
        previewDirectory: URL? = nil
    ) -> ChatMediaUploadUseCase {
        ChatMediaUploadUseCase(
            imageStorageRepository: imageRepository,
            videoStorageRepository: videoRepository,
            sendingRepository: sendingRepository,
            attachmentImageLoader: attachmentImageLoader,
            currentUserProvider: {
                ChatMessageSenderSnapshot(
                    senderID: "me@example.com",
                    senderNickname: "나",
                    senderAvatarPath: "avatars/me.jpg"
                )
            },
            dateProvider: { Date(timeIntervalSince1970: 123) },
            previewDirectoryProvider: { previewDirectory ?? FileManager.default.temporaryDirectory },
            fileManager: .default
        )
    }

    private func makeProcessedImage(
        index: Int = 0,
        sha256: String = "image-sha"
    ) throws -> ProcessedImage {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try Data([9, 9, 9]).write(to: fileURL)
        return ProcessedImage(
            index: index,
            originalFileURL: fileURL,
            thumbData: Data([1, 2, UInt8(index + 3)]),
            originalWidth: 100 + index,
            originalHeight: 80 + index,
            bytesOriginal: 3,
            sha256: sha256
        )
    }

    private func makePreparedVideo() throws -> PreparedVideo {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try Data([7, 7, 7]).write(to: fileURL)
        return PreparedVideo(
            compressedFileURL: fileURL,
            thumbnailData: Data([3, 2, 1]),
            sha256: "video-sha",
            duration: 12.5,
            width: 1280,
            height: 720,
            sizeBytes: 3,
            approxBitrateMbps: 4.5,
            preset: .standard720
        )
    }

    private func makeAttachment(hash: String) -> ChatAttachment {
        ChatAttachment(
            type: .image,
            index: 0,
            pathThumb: "rooms/room-1/messages/message-1/images/\(hash)/thumb.jpg",
            pathOriginal: "rooms/room-1/messages/message-1/images/\(hash)/original.jpg",
            width: 100,
            height: 80,
            bytesOriginal: 3,
            hash: hash,
            blurhash: nil,
            duration: nil
        )
    }

    private func makeRoom(id: String?) -> ChatRoom {
        ChatRoom(
            ID: id,
            roomName: "Test Room",
            roomDescription: "Test Description",
            participants: ["me@example.com"],
            creatorID: "owner@example.com",
            createdAt: Date(timeIntervalSince1970: 0),
            thumbPath: nil,
            originalPath: nil,
            lastMessageAt: nil,
            lastMessage: nil,
            lastMessageSenderID: nil,
            seq: 0,
            isClosed: false,
            activeAnnouncementID: nil,
            activeAnnouncement: nil,
            announcementUpdatedAt: nil
        )
    }
}

private final class FirebaseImageStorageRepositoryFake: FirebaseImageStorageRepositoryProtocol {
    struct UploadCall {
        let pairs: [ProcessedImage]
        let roomID: String
        let messageID: String
    }

    var uploadResult: [ChatAttachment] = []
    var uploadError: Error?
    private(set) var uploadCalls: [UploadCall] = []

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
    ) async throws -> [ChatAttachment] {
        uploadCalls.append(UploadCall(pairs: pairs, roomID: roomID, messageID: messageID))
        onProgress?(0.25)
        if let uploadError { throw uploadError }
        onProgress?(1.0)
        return uploadResult
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

private final class FirebaseVideoStorageRepositoryFake: FirebaseVideoStorageRepositoryProtocol {
    struct FileUploadCall {
        let localURL: URL
        let path: String
        let contentType: String
    }

    struct DataUploadCall {
        let data: Data
        let path: String
        let contentType: String
    }

    var fileUploadError: Error?
    var dataUploadError: Error?
    private(set) var fileUploadCalls: [FileUploadCall] = []
    private(set) var dataUploadCalls: [DataUploadCall] = []

    func putVideoFileToStorage(
        localURL: URL,
        path: String,
        contentType: String,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        fileUploadCalls.append(FileUploadCall(localURL: localURL, path: path, contentType: contentType))
        onProgress(0.5)
        if let fileUploadError { throw fileUploadError }
        onProgress(1.0)
    }

    func putVideoDataToStorage(data: Data, path: String, contentType: String) async throws {
        dataUploadCalls.append(DataUploadCall(data: data, path: path, contentType: contentType))
        if let dataUploadError { throw dataUploadError }
    }

    func deleteVideoFromStorage(path: String) {}

    func setDataFallbackLimitMB(_ mb: Int) {}
}

private final class ChatMediaMessageSendingRepositorySpy: ChatMediaMessageSendingRepositoryProtocol {
    struct PreflightCall: Equatable {
        let roomID: String
        let messageID: String
        let kind: String
    }

    struct ImageCall {
        let room: ChatRoom
        let attachments: [ChatAttachment]
        let senderAvatarPath: String?
        let clientMessageID: String?
    }

    struct VideoCall {
        let roomID: String
        let payload: VideoMetaPayload
        let senderAvatarPath: String?
    }

    struct FailedVideoCall {
        let roomID: String
        let senderID: String
        let senderNickname: String
        let localURL: URL
        let thumbData: Data?
        let duration: Double
        let width: Int
        let height: Int
        let presetCode: String
    }

    private(set) var imageCalls: [ImageCall] = []
    private(set) var videoCalls: [VideoCall] = []
    private(set) var failedVideoCalls: [FailedVideoCall] = []
    private(set) var preflightCalls: [PreflightCall] = []
    var preflightError: Error?

    var isSocketConnected = true

    func preflightMediaUpload(
        roomID: String,
        messageID: String,
        kind: String
    ) async throws {
        preflightCalls.append(PreflightCall(roomID: roomID, messageID: messageID, kind: kind))
        if let preflightError {
            throw preflightError
        }
    }

    func sendImages(
        _ room: ChatRoom,
        attachments: [ChatAttachment],
        senderAvatarPath: String?,
        clientMessageID: String?
    ) async throws {
        imageCalls.append(ImageCall(
            room: room,
            attachments: attachments,
            senderAvatarPath: senderAvatarPath,
            clientMessageID: clientMessageID
        ))
    }

    func sendVideo(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?
    ) async throws {
        videoCalls.append(VideoCall(
            roomID: roomID,
            payload: payload,
            senderAvatarPath: senderAvatarPath
        ))
    }

    func sendFailedVideo(
        roomID: String,
        senderID: String,
        senderNickname: String,
        localURL: URL,
        thumbData: Data?,
        duration: Double,
        width: Int,
        height: Int,
        presetCode: String
    ) {
        failedVideoCalls.append(FailedVideoCall(
            roomID: roomID,
            senderID: senderID,
            senderNickname: senderNickname,
            localURL: localURL,
            thumbData: thumbData,
            duration: duration,
            width: width,
            height: height,
            presetCode: presetCode
        ))
    }
}

private actor ChatAttachmentImageLoaderSpy: ChatAttachmentImageLoading {
    private var outgoingPreviewEntries: [(data: Data, key: String)] = []

    func cacheImagesIfNeeded(for message: ChatMessage, maxBytes: Int) async -> [UIImage] { [] }
    func cachedImage(for path: String) async -> UIImage? { nil }
    func loadImage(for path: String, maxBytes: Int) async throws -> UIImage {
        throw TestError.unimplemented
    }
    func prefetchThumbnails(for messages: [ChatMessage], maxBytes: Int, maxConcurrent: Int) async {}
    func prefetchImages(paths: [String], maxBytes: Int, maxConcurrent: Int) async {}

    func storeOutgoingPreview(data: Data, forKey key: String) async {
        outgoingPreviewEntries.append((data: data, key: key))
    }

    func cachedOutgoingPreview(forKey key: String) async -> UIImage? { nil }

    func outgoingPreviewKeys() -> [String] {
        outgoingPreviewEntries.map(\.key)
    }
}

private enum TestError: Error {
    case unimplemented
}
