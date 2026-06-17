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
        let pair = try makeImagePair()

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
        let pair = try makeImagePair()
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
        let pair = try makeImagePair()
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
            messageID: "video-1"
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

    private func makeImagePair() throws -> DefaultMediaProcessingService.ImagePair {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try Data([9, 9, 9]).write(to: fileURL)
        return DefaultMediaProcessingService.ImagePair(
            index: 0,
            originalFileURL: fileURL,
            thumbData: Data([1, 2, 3]),
            originalWidth: 100,
            originalHeight: 80,
            bytesOriginal: 3,
            sha256: "image-sha"
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
