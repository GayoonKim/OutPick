//
//  ChatOutgoingOutboxUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 6/24/26.
//

import Foundation
import Testing
import UIKit
@testable import OutPick

struct ChatOutgoingOutboxUseCaseTests {
    @Test func retryPayloadUsesUploadedImagePayloadForFinalizeOnlyRetry() async throws {
        let persistence = ChatOutgoingOutboxPersistenceFake()
        let useCase = makeUseCase(persistence: persistence)
        let message = makeMessage(id: "image-1")
        let pair = try makeProcessedImage()
        let uploaded = makeAttachment(messageID: "image-1")

        await useCase.stageImageMessage(message, pairs: [pair])
        await useCase.markImageUploadCompleted(messageID: "image-1", attachments: [uploaded])

        let payload = await useCase.retryPayload(for: message, room: makeRoom())

        guard case let .finalizeImages(_, messageID, attachments) = payload else {
            Issue.record("uploaded image outbox는 finalize retry payload여야 합니다.")
            return
        }
        #expect(messageID == "image-1")
        #expect(attachments == [uploaded])
    }

    @Test func retryPayloadUsesLocalImagePayloadForUploadRetry() async throws {
        let persistence = ChatOutgoingOutboxPersistenceFake()
        let useCase = makeUseCase(persistence: persistence)
        let message = makeMessage(id: "image-2")
        let pair = try makeProcessedImage()

        await useCase.stageImageMessage(message, pairs: [pair])

        let payload = await useCase.retryPayload(for: message, room: makeRoom())

        guard case let .uploadImages(_, messageID, pairs) = payload else {
            Issue.record("local image outbox는 upload retry payload여야 합니다.")
            return
        }
        #expect(messageID == "image-2")
        #expect(pairs.count == 1)
        #expect(pairs.first?.sha256 == pair.sha256)
    }

    @Test func completeServerConfirmedMessageDeletesOutboxRecord() async throws {
        let persistence = ChatOutgoingOutboxPersistenceFake()
        let useCase = makeUseCase(persistence: persistence)
        let failed = makeMessage(id: "text-1", isFailed: true)
        let confirmed = makeMessage(id: "text-1", isFailed: false)

        await useCase.stageTextMessage(failed)
        #expect(await persistence.record(messageID: "text-1") != nil)

        await useCase.completeServerConfirmedMessage(confirmed)

        #expect(await persistence.record(messageID: "text-1") == nil)
        #expect(await persistence.message(messageID: "text-1", roomID: "room-1")?.isFailed == false)
    }

    @Test func completeServerConfirmedMessagePersistsReceiptWithoutOutboxRecord() async {
        let persistence = ChatOutgoingOutboxPersistenceFake()
        let useCase = makeUseCase(persistence: persistence)
        let confirmed = makeMessage(id: "text-without-outbox", isFailed: false)

        await useCase.completeServerConfirmedMessage(confirmed)

        #expect(await persistence.message(
            messageID: "text-without-outbox",
            roomID: "room-1"
        )?.isFailed == false)
    }

    private func makeUseCase(
        persistence: ChatOutgoingOutboxPersistenceFake
    ) -> ChatOutgoingOutboxUseCase {
        let outboxRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatOutgoingOutboxUseCaseTests-\(UUID().uuidString)", isDirectory: true)
        return ChatOutgoingOutboxUseCase(
            outboxPersistence: persistence,
            messagePersistence: persistence,
            imageStorageRepository: FirebaseImageStorageRepositoryFake(),
            videoStorageRepository: FirebaseVideoStorageRepositoryFake(),
            fileManager: .default,
            dateProvider: { Date(timeIntervalSince1970: 123) },
            outboxRootProvider: { outboxRoot }
        )
    }

    private func makeMessage(id: String, isFailed: Bool = false) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: 0,
            roomID: "room-1",
            senderUID: "me@example.com",
            senderEmail: nil,
            senderNickname: "나",
            msg: "",
            sentAt: Date(timeIntervalSince1970: 100),
            attachments: [],
            replyPreview: nil,
            isFailed: isFailed
        )
    }

    private func makeRoom() -> ChatRoom {
        ChatRoom(
            id: "room-1",
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

    private func makeAttachment(messageID: String) -> OutPick.Attachment {
        OutPick.Attachment(
            type: .image,
            index: 0,
            pathThumb: "rooms/room-1/messages/\(messageID)/images/image-sha/thumb.jpg",
            pathOriginal: "rooms/room-1/messages/\(messageID)/images/image-sha/original.jpg",
            width: 100,
            height: 80,
            bytesOriginal: 3,
            hash: "image-sha",
            blurhash: nil,
            duration: nil
        )
    }
}

private actor ChatOutgoingOutboxPersistenceFake: ChatOutgoingOutboxPersisting, ChatFailedOutgoingMessagePersisting {
    private var records: [String: ChatOutgoingOutboxRecord] = [:]
    private var messages: [String: ChatMessage] = [:]

    func saveChatMessages(_ messages: [ChatMessage]) async throws {
        for message in messages {
            self.messages[key(messageID: message.ID, roomID: message.roomID)] = message
        }
    }

    func fetchMessage(id messageID: String, inRoom roomID: String) async throws -> ChatMessage? {
        messages[key(messageID: messageID, roomID: roomID)]
    }

    func hardDeleteMessage(id messageID: String, inRoom roomID: String) async throws {
        messages.removeValue(forKey: key(messageID: messageID, roomID: roomID))
    }

    func saveOutgoingOutboxRecord(_ record: ChatOutgoingOutboxRecord) async throws {
        records[record.messageID] = record
    }

    func fetchOutgoingOutboxRecord(messageID: String) async throws -> ChatOutgoingOutboxRecord? {
        records[messageID]
    }

    func deleteOutgoingOutboxRecord(messageID: String) async throws {
        records.removeValue(forKey: messageID)
    }

    func record(messageID: String) -> ChatOutgoingOutboxRecord? {
        records[messageID]
    }

    func message(messageID: String, roomID: String) -> ChatMessage? {
        messages[key(messageID: messageID, roomID: roomID)]
    }

    private func key(messageID: String, roomID: String) -> String {
        "\(roomID)::\(messageID)"
    }
}

private final class FirebaseImageStorageRepositoryFake: FirebaseImageStorageRepositoryProtocol {
    private(set) var deletedPaths: [String] = []

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

    func deleteImageFromStorage(path: String) {
        deletedPaths.append(path)
    }

    func setDataFallbackLimitMB(_ mb: Int) {}
}

private final class FirebaseVideoStorageRepositoryFake: FirebaseVideoStorageRepositoryProtocol {
    private(set) var deletedPaths: [String] = []

    func putVideoFileToStorage(
        localURL: URL,
        path: String,
        contentType: String,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        throw TestError.unimplemented
    }

    func putVideoDataToStorage(data: Data, path: String, contentType: String) async throws {
        throw TestError.unimplemented
    }

    func deleteVideoFromStorage(path: String) {
        deletedPaths.append(path)
    }

    func setDataFallbackLimitMB(_ mb: Int) {}
}

private enum TestError: Error {
    case unimplemented
}
