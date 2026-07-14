//
//  ChatPendingMediaUploadStoreTests.swift
//  OutPickTests
//
//  Created by Codex on 6/18/26.
//

import Foundation
import Testing
@testable import OutPick

@MainActor
struct ChatPendingMediaUploadStoreTests {
    @Test func stageImageUploadTracksInitialStateAndRetryPayloadAfterFailure() throws {
        let store = ChatPendingMediaUploadStore()
        let pair = try makeProcessedImage()

        let staged = store.stageImageUpload(
            room: makeRoom(id: "room-1"),
            roomID: "room-1",
            messageID: "message-1",
            pairs: [pair]
        )

        #expect(staged == true)
        #expect(store.imageUploadState(for: "message-1") == .uploading(0))
        #expect(store.retryPayload(for: "message-1") == nil)

        store.failImageUpload(for: "message-1")
        let payload = try #require(store.retryPayload(for: "message-1"))
        #expect(payload.roomID == "room-1")
        #expect(payload.messageID == "message-1")
        #expect(payload.pairs.count == 1)
    }

    @Test func startImageUploadTaskRejectsDuplicateTaskUntilFinished() throws {
        let store = ChatPendingMediaUploadStore()
        let pair = try makeProcessedImage()
        _ = store.stageImageUpload(
            room: makeRoom(id: "room-1"),
            roomID: "room-1",
            messageID: "message-1",
            pairs: [pair]
        )
        let firstTask = Task<Void, Never> {}
        let secondTask = Task<Void, Never> {}

        #expect(store.startImageUploadTask(firstTask, for: "message-1") == true)
        #expect(store.startImageUploadTask(secondTask, for: "message-1") == false)

        store.finishImageUploadTask(for: "message-1")
        #expect(store.startImageUploadTask(secondTask, for: "message-1") == true)

        firstTask.cancel()
        secondTask.cancel()
    }

    @Test func completeImageUploadRemovesStateAndPayload() throws {
        let store = ChatPendingMediaUploadStore()
        let pair = try makeProcessedImage()
        _ = store.stageImageUpload(
            room: makeRoom(id: "room-1"),
            roomID: "room-1",
            messageID: "message-1",
            pairs: [pair]
        )

        store.completeImageUpload(for: "message-1")

        #expect(store.imageUploadState(for: "message-1") == nil)
        #expect(store.retryPayload(for: "message-1") == nil)
    }

    @Test func videoUploadTracksStateAndRejectsDuplicateTaskUntilFinished() throws {
        let store = ChatPendingMediaUploadStore()

        let staged = store.stageVideoUpload(
            roomID: "room-1",
            messageID: "video-1",
            prepared: try makePreparedVideo()
        )
        let firstTask = Task<Void, Never> {}
        let secondTask = Task<Void, Never> {}

        #expect(staged == true)
        #expect(store.videoUploadState(for: "video-1") == .uploading(0))
        store.setVideoUploadState(.uploading(0.5), for: "video-1")
        #expect(store.uploadState(for: "video-1") == .uploading(0.5))
        #expect(store.startVideoUploadTask(firstTask, for: "video-1") == true)
        #expect(store.startVideoUploadTask(secondTask, for: "video-1") == false)

        store.finishVideoUploadTask(for: "video-1")
        #expect(store.startVideoUploadTask(secondTask, for: "video-1") == true)
        store.completeVideoUpload(for: "video-1")
        #expect(store.videoUploadState(for: "video-1") == nil)

        firstTask.cancel()
        secondTask.cancel()
    }

    @Test func retryPayloadUsesUploadedImageAttachmentsWhenFinalizeFailed() throws {
        let store = ChatPendingMediaUploadStore()
        let pair = try makeProcessedImage()
        let attachment = makeAttachment()
        _ = store.stageImageUpload(
            room: makeRoom(id: "room-1"),
            roomID: "room-1",
            messageID: "message-1",
            pairs: [pair]
        )

        store.setUploadedImageAttachments([attachment], for: "message-1")
        store.failImageUpload(for: "message-1")

        guard case let .finalizeImages(_, roomID, messageID, attachments) = store.mediaRetryPayload(for: "message-1") else {
            Issue.record("Expected finalizeImages retry payload")
            return
        }
        #expect(roomID == "room-1")
        #expect(messageID == "message-1")
        #expect(attachments == [attachment])
    }

    @Test func retryPayloadUsesUploadedVideoPayloadWhenFinalizeFailed() throws {
        let store = ChatPendingMediaUploadStore()
        let prepared = try makePreparedVideo()
        let payload = VideoMetaPayload(
            roomID: "room-1",
            messageID: "video-1",
            storagePath: "rooms/room-1/messages/video-1/video/video.mp4",
            thumbnailPath: "rooms/room-1/messages/video-1/video/thumb.jpg",
            duration: prepared.duration,
            width: prepared.width,
            height: prepared.height,
            sizeBytes: prepared.sizeBytes,
            approxBitrateMbps: prepared.approxBitrateMbps,
            preset: "standard720"
        )
        _ = store.stageVideoUpload(
            roomID: "room-1",
            messageID: "video-1",
            prepared: prepared
        )

        store.setUploadedVideoPayload(payload, for: "video-1")
        store.setVideoUploadState(.failed, for: "video-1")

        guard case let .finalizeVideo(roomID, messageID, retryPayload) = store.mediaRetryPayload(for: "video-1") else {
            Issue.record("Expected finalizeVideo retry payload")
            return
        }
        #expect(roomID == "room-1")
        #expect(messageID == "video-1")
        #expect(retryPayload.messageID == "video-1")
        #expect(retryPayload.storagePath == payload.storagePath)
    }

    private func makeProcessedImage() throws -> ProcessedImage {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try Data([9, 9, 9]).write(to: fileURL)
        return ProcessedImage(
            index: 0,
            originalFileURL: fileURL,
            thumbData: Data([1, 2, 3]),
            originalWidth: 100,
            originalHeight: 80,
            bytesOriginal: 3,
            sha256: "image-sha"
        )
    }

    private func makeAttachment() -> OutPick.Attachment {
        OutPick.Attachment(
            type: .image,
            index: 0,
            pathThumb: "rooms/room-1/messages/message-1/images/image-sha/thumb.jpg",
            pathOriginal: "rooms/room-1/messages/message-1/images/image-sha/original.jpg",
            width: 100,
            height: 80,
            bytesOriginal: 3,
            hash: "image-sha",
            blurhash: nil,
            duration: nil
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

    private func makeRoom(id: String) -> ChatRoom {
        ChatRoom(
            id: id,
            roomName: "Test Room",
            roomDescription: "Test Description",
            participants: ["me@example.com"],
            creatorUID: "owner@example.com",
            createdAt: Date(timeIntervalSince1970: 0),
            thumbPath: nil,
            originalPath: nil,
            lastMessageAt: nil,
            lastMessage: nil,
            lastMessageSenderUID: nil,
            seq: 0,
            isClosed: false,
            activeAnnouncementID: nil,
            activeAnnouncement: nil,
            announcementUpdatedAt: nil
        )
    }
}
