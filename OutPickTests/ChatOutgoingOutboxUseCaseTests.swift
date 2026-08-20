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

        let restoredMessage = try #require(await persistence.message(messageID: "image-2", roomID: "room-1"))
        let restoredAttachment = try #require(restoredMessage.attachments.first)
        #expect(restoredAttachment.pathThumb == restoredAttachment.pathOriginal)
        #expect(restoredAttachment.pathOriginal.contains("_original.jpg"))

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

    @Test func batchReconciliationDeletesOnlyServerConfirmedOutboxRecords() async throws {
        let persistence = ChatOutgoingOutboxPersistenceFake()
        let useCase = makeUseCase(persistence: persistence)
        let firstFailed = makeMessage(id: "text-1", isFailed: true)
        let secondFailed = makeMessage(id: "text-2", isFailed: true)
        let unresolved = makeMessage(id: "text-3", isFailed: true)

        await useCase.stageTextMessage(firstFailed)
        await useCase.stageTextMessage(secondFailed)
        await useCase.stageTextMessage(unresolved)

        var firstConfirmed = firstFailed
        firstConfirmed.isFailed = false
        var secondConfirmed = secondFailed
        secondConfirmed.isFailed = false
        try await persistence.saveChatMessages([firstConfirmed, secondConfirmed])

        try await useCase.reconcileServerConfirmedMessages([firstConfirmed, secondConfirmed])

        #expect(await persistence.record(messageID: "text-1") == nil)
        #expect(await persistence.record(messageID: "text-2") == nil)
        #expect(await persistence.record(messageID: "text-3") != nil)
    }

    @Test func cancelPendingMessagesDeletesOnlyTargetRoomOutboxAndFailedMessages() async {
        let persistence = ChatOutgoingOutboxPersistenceFake()
        let useCase = makeUseCase(persistence: persistence)
        let removedRoomMessage = makeMessage(id: "removed-room", roomID: "room-1", isFailed: true)
        let otherRoomMessage = makeMessage(id: "other-room", roomID: "room-2", isFailed: true)

        await useCase.stageTextMessage(removedRoomMessage)
        await useCase.stageTextMessage(otherRoomMessage)
        await useCase.cancelPendingMessages(roomID: "room-1")

        #expect(await persistence.record(messageID: "removed-room") == nil)
        #expect(await persistence.message(messageID: "removed-room", roomID: "room-1") == nil)
        #expect(await persistence.record(messageID: "other-room") != nil)
        #expect(await persistence.message(messageID: "other-room", roomID: "room-2")?.isFailed == true)
    }

    @Test func failedMediaIsRemovedAfterSevenDayRetention() async throws {
        let persistence = ChatOutgoingOutboxPersistenceFake()
        let outboxRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatOutgoingOutboxRetentionTests-\(UUID().uuidString)", isDirectory: true)
        let initial = makeUseCase(
            persistence: persistence,
            now: Date(timeIntervalSince1970: 100),
            outboxRoot: outboxRoot
        )
        let message = makeMessage(id: "expired-image", isFailed: true)
        await initial.stageImageMessage(message, pairs: [try makeProcessedImage()])
        await initial.markFailed(message: message, error: TestError.unimplemented)

        let afterRetention = makeUseCase(
            persistence: persistence,
            now: Date(timeIntervalSince1970: 100 + 7 * 24 * 60 * 60 + 1),
            outboxRoot: outboxRoot
        )
        let pending = await afterRetention.pendingMediaRecords(roomID: "room-1")

        #expect(pending.isEmpty)
        #expect(await persistence.record(messageID: message.ID) == nil)
        #expect(await persistence.message(messageID: message.ID, roomID: message.roomID) == nil)
    }

    @Test func mediaReservationPersistsOnlySessionIdentityUntilTerminalFailure() async throws {
        let persistence = ChatOutgoingOutboxPersistenceFake()
        let useCase = makeUseCase(persistence: persistence)
        let message = makeMessage(id: "image-session")
        let pair = try makeProcessedImage()
        await useCase.stageImageMessage(message, pairs: [pair])
        let reservation = ChatMediaUploadReservation(
            uploadID: message.ID,
            clientMutationID: "mutation-1",
            processingStatus: .uploading,
            targets: [ChatMediaUploadTarget(
                attachmentID: "attachment-1",
                sourceIndex: 0,
                path: "room/user/upload/attachment-1/source",
                signedURL: URL(string: "https://storage.example/signed-put")!,
                requiredHeaders: ["Content-Type": "image/jpeg"],
                contentType: "image/jpeg",
                sizeBytes: 3,
                sha256: String(repeating: "a", count: 64)
            )],
            expiresAt: Date(timeIntervalSince1970: 7_200)
        )

        await useCase.markMediaReservation(messageID: message.ID, reservation: reservation)

        let active = try #require(await persistence.record(messageID: message.ID))
        #expect(active.stage == .uploading)
        #expect(active.clientMutationID == "mutation-1")
        #expect(active.sessionPayloadJSON?.contains("signed-put") == false)
        #expect(active.sessionPayloadJSON?.contains("requiredHeaders") == false)

        await useCase.markMediaProcessing(
            messageID: message.ID,
            snapshot: ChatMediaProcessingSnapshot(
                uploadID: message.ID,
                processingStatus: .failed,
                messageID: nil,
                seq: nil,
                retryable: true,
                failureCode: "worker_failed"
            )
        )
        let failed = try #require(await persistence.record(messageID: message.ID))
        #expect(failed.stage == .failed)
        #expect(failed.sessionPayloadJSON == nil)
        #expect(failed.requiresManualMediaRetryAfterRestore == true)

        let pending = await useCase.pendingMediaRecords(roomID: message.roomID)
        #expect(pending.map(\.messageID) == [message.ID])
        #expect(await useCase.mediaSessionPayload(messageID: message.ID) == nil)
        guard case let .uploadImages(_, retryMessageID, pairs) = await useCase.retryPayload(
            messageID: message.ID,
            room: makeRoom()
        ) else {
            Issue.record("terminal media failure는 session 없이 local retry payload로 복원돼야 합니다.")
            return
        }
        #expect(retryMessageID == message.ID)
        #expect(pairs.count == 1)
    }

    @Test func restoreManualRetryClearsSessionAndKeepsLocalRetryPayload() async throws {
        let persistence = ChatOutgoingOutboxPersistenceFake()
        let useCase = makeUseCase(persistence: persistence)
        let message = makeMessage(id: "restore-manual")
        await useCase.stageImageMessage(message, pairs: [try makeProcessedImage()])
        await useCase.markMediaReservation(
            messageID: message.ID,
            reservation: ChatMediaUploadReservation(
                uploadID: message.ID,
                clientMutationID: "mutation-restore",
                processingStatus: .uploading,
                targets: [],
                expiresAt: Date(timeIntervalSince1970: 7_200)
            )
        )

        await useCase.markMediaRestoreRequiresManualRetry(messageID: message.ID)

        let failed = try #require(await persistence.record(messageID: message.ID))
        #expect(failed.stage == .failed)
        #expect(failed.processingStatus == ChatMediaServerProcessingStatus.failed.rawValue)
        #expect(failed.sessionPayloadJSON == nil)
        #expect(failed.requiresManualMediaRetryAfterRestore)
        guard case let .uploadImages(_, restoredID, pairs) = await useCase.retryPayload(
            messageID: message.ID,
            room: makeRoom()
        ) else {
            Issue.record("복원 실패는 local source 기반 수동 재시도를 유지해야 합니다.")
            return
        }
        #expect(restoredID == message.ID)
        #expect(pairs.count == 1)
    }

    private func makeUseCase(
        persistence: ChatOutgoingOutboxPersistenceFake,
        now: Date = Date(timeIntervalSince1970: 123),
        outboxRoot: URL? = nil
    ) -> ChatOutgoingOutboxUseCase {
        let resolvedOutboxRoot = outboxRoot ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatOutgoingOutboxUseCaseTests-\(UUID().uuidString)", isDirectory: true)
        return ChatOutgoingOutboxUseCase(
            outboxPersistence: persistence,
            messagePersistence: persistence,
            imageStorageRepository: FirebaseImageStorageRepositoryFake(),
            videoStorageRepository: FirebaseVideoStorageRepositoryFake(),
            fileManager: .default,
            dateProvider: { now },
            outboxRootProvider: { resolvedOutboxRoot }
        )
    }

    private func makeMessage(
        id: String,
        roomID: String = "room-1",
        isFailed: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: 0,
            roomID: roomID,
            senderUID: "me@example.com",
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

    func fetchOutgoingOutboxRecords(messageIDs: [String]) async throws -> [ChatOutgoingOutboxRecord] {
        messageIDs.compactMap { records[$0] }
    }

    func fetchOutgoingOutboxRecords(roomID: String) async throws -> [ChatOutgoingOutboxRecord] {
        records.values.filter { $0.roomID == roomID }
    }

    func deleteOutgoingOutboxRecord(messageID: String) async throws {
        records.removeValue(forKey: messageID)
    }

    func deleteOutgoingOutboxRecords(messageIDs: [String]) async throws {
        for messageID in messageIDs {
            records.removeValue(forKey: messageID)
        }
    }

    func deleteOutgoingOutboxRecords(roomID: String) async throws {
        records = records.filter { $0.value.roomID != roomID }
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
