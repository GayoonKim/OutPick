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
        #expect(message.senderUID == "me@example.com")
        #expect(message.senderNickname == "나")
        #expect(message.senderAvatarPath == "avatars/me.jpg")
        #expect(message.attachments.map(\.index) == [1, 2])
        #expect(message.attachments.allSatisfy { $0.type == .image })
        #expect(message.attachments.map(\.pathThumb) == [
            second.originalFileURL.absoluteString,
            first.originalFileURL.absoluteString
        ])
        #expect(message.attachments.allSatisfy { $0.pathThumb == $0.pathOriginal })

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
        #expect(message.senderUID == "me@example.com")
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
        let firstPair = try makeProcessedImage(index: 0, sha256: "image-sha-1")
        let secondPair = try makeProcessedImage(index: 1, sha256: "image-sha-2")
        let firstAttachment = makeAttachment(hash: "image-sha-1")
        let secondAttachment = makeAttachment(hash: "image-sha-2")
        imageRepository.uploadResult = [firstAttachment, secondAttachment]
        var progressValues: [Double] = []

        let attachments = try await useCase.uploadPendingImages(
            pairs: [firstPair, secondPair],
            roomID: "room-1",
            messageID: "message-1",
            onProgress: { progressValues.append($0) }
        )
        try await useCase.sendUploadedImages(
            room: makeRoom(id: "room-1"),
            attachments: attachments,
            clientMessageID: "message-1",
            ensureReservation: false
        )

        #expect(sendingRepository.preflightCalls == [
            .init(
                roomID: "room-1",
                messageID: "message-1",
                kind: "images",
                attachmentCount: 2,
                expectedPathCount: 4
            )
        ])
        #expect(imageRepository.uploadCalls.count == 1)
        #expect(imageRepository.uploadCalls.first?.roomID == "room-1")
        #expect(imageRepository.uploadCalls.first?.messageID == "message-1")
        #expect(progressValues == [0.25, 1.0])
        #expect(FileManager.default.fileExists(atPath: firstPair.originalFileURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: secondPair.originalFileURL.path) == false)
        #expect(sendingRepository.imageCalls.count == 1)
        #expect(sendingRepository.imageCalls.first?.attachments == [firstAttachment, secondAttachment])
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
        try await useCase.sendUploadedVideo(roomID: "room-1", payload: payload, ensureReservation: false)

        #expect(sendingRepository.preflightCalls == [
            .init(
                roomID: "room-1",
                messageID: "video-1",
                kind: "video",
                attachmentCount: 1,
                expectedPathCount: 2
            )
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
        #expect(sendingRepository.failedVideoCalls.first?.senderUID == "me@example.com")
        #expect(sendingRepository.failedVideoCalls.first?.senderNickname == "나")
        #expect(sendingRepository.failedVideoCalls.first?.localURL == prepared.compressedFileURL)
        #expect(sendingRepository.failedVideoCalls.first?.presetCode == "standard720")
    }

    @Test func signedPutResponseLossIsRecoveredByServerReconciliationBeforeFinalize() async throws {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let uploader = ChatMediaForegroundUploaderFake()
        uploader.uploadError = TestError.unimplemented
        let sha256 = String(repeating: "a", count: 64)
        let pair = try makeProcessedImage(sha256: sha256)
        let target = ChatMediaUploadTarget(
            attachmentID: "attachment-1",
            sourceIndex: 0,
            path: "room/user/upload/attachment-1/source",
            signedURL: URL(string: "https://storage.example/signed-put")!,
            requiredHeaders: ["content-type": "image/jpeg"],
            contentType: "image/jpeg",
            sizeBytes: 3,
            sha256: sha256
        )
        sendingRepository.reserveResult = ChatMediaUploadReservation(
            uploadID: "upload-1",
            clientMutationID: "mutation-1",
            processingStatus: .uploading,
            targets: [target],
            expiresAt: Date().addingTimeInterval(86_400)
        )
        sendingRepository.refreshResult = ChatMediaUploadReservation(
            uploadID: "upload-1",
            clientMutationID: "mutation-1",
            processingStatus: .uploading,
            targets: [],
            expiresAt: Date().addingTimeInterval(86_400)
        )
        sendingRepository.finalizeResult = ChatMediaProcessingSnapshot(
            uploadID: "upload-1",
            processingStatus: .queued,
            messageID: nil,
            seq: nil,
            retryable: true,
            failureCode: nil
        )
        let turns = ChatMediaUploadTurnQueue()
        let useCase = makeUseCase(
            sendingRepository: sendingRepository,
            foregroundUploader: uploader,
            uploadTurnQueue: turns
        )

        let snapshot = try await useCase.enqueueImageProcessing(
            pairs: [pair],
            roomID: "room-1",
            uploadID: "upload-1",
            clientMutationID: "mutation-1",
            onReservation: { _ in },
            onProgress: { _ in }
        )

        #expect(snapshot.processingStatus == .queued)
        #expect(await turns.snapshot(lane: .images).activeUploadIDs == ["upload-1"])
        await useCase.finishImageUploadTurn(uploadID: "upload-1")
        #expect(await turns.snapshot(lane: .images).activeUploadIDs.isEmpty)
        #expect(uploader.uploadedSourceIndexes == [0])
        #expect(sendingRepository.refreshCallCount == 0)
        #expect(sendingRepository.finalizeCallCount == 1)
        try? FileManager.default.removeItem(at: pair.originalFileURL)
    }

    @Test func finalizeIncompleteRefreshesOnlyMissingFilesAndRetriesFinalize() async throws {
        let repository = ChatMediaMessageSendingRepositorySpy()
        let uploader = ChatMediaForegroundUploaderFake()
        let pair = try makeProcessedImage(sha256: String(repeating: "a", count: 64))
        defer { try? FileManager.default.removeItem(at: pair.originalFileURL) }
        let target = ChatMediaUploadTarget(attachmentID: "attachment", sourceIndex: 0,
            path: "room/user/upload/attachment/source",
            signedURL: URL(string: "https://storage.example/put")!, requiredHeaders: [:],
            contentType: "image/jpeg", sizeBytes: 3, sha256: String(repeating: "a", count: 64))
        repository.reserveResult = ChatMediaUploadReservation(uploadID: "upload", clientMutationID: "mutation",
            processingStatus: .uploading, targets: [target], expiresAt: Date().addingTimeInterval(1000))
        repository.refreshResult = repository.reserveResult
        repository.finalizeOutcomes = [.failure(ChatMediaUploadError.uploadIncomplete),
            .success(ChatMediaProcessingSnapshot(uploadID: "upload", processingStatus: .queued,
                messageID: nil, seq: nil, retryable: true, failureCode: nil))]
        let useCase = makeUseCase(sendingRepository: repository, foregroundUploader: uploader)
        let result = try await useCase.enqueueImageProcessing(pairs: [pair], roomID: "room",
            uploadID: "upload", clientMutationID: "mutation", onReservation: { _ in }, onProgress: { _ in })
        #expect(result.processingStatus == .queued)
        #expect(repository.refreshCallCount == 1)
        #expect(repository.finalizeCallCount == 2)
        #expect(repository.cancelCallCount == 0)
        #expect(uploader.uploadedSourceIndexes == [0, 0])
    }

    @Test func reservedUploadFailureCancelsServerReservationToReleaseSlot() async throws {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let uploader = ChatMediaForegroundUploaderFake()
        uploader.uploadError = URLError(.networkConnectionLost)
        let sha256 = String(repeating: "c", count: 64)
        let pair = try makeProcessedImage(sha256: sha256)
        sendingRepository.reserveResult = ChatMediaUploadReservation(
            uploadID: "upload-cancel",
            clientMutationID: "mutation-cancel",
            processingStatus: .uploading,
            targets: [ChatMediaUploadTarget(
                attachmentID: "attachment-cancel",
                sourceIndex: 0,
                path: "room/user/upload/attachment-cancel/source",
                signedURL: URL(string: "https://storage.example/signed-put")!,
                requiredHeaders: ["content-type": "image/jpeg"],
                contentType: "image/jpeg",
                sizeBytes: 3,
                sha256: sha256
            )],
            expiresAt: Date().addingTimeInterval(86_400)
        )
        sendingRepository.refreshResult = sendingRepository.reserveResult
        sendingRepository.finalizeError = ChatMediaUploadError.uploadIncomplete
        sendingRepository.cancelResult = ChatMediaProcessingSnapshot(
            uploadID: "upload-cancel",
            processingStatus: .canceled,
            messageID: nil,
            seq: nil,
            retryable: true,
            failureCode: nil
        )
        let useCase = makeUseCase(
            sendingRepository: sendingRepository,
            foregroundUploader: uploader
        )

        do {
            _ = try await useCase.enqueueImageProcessing(
                pairs: [pair],
                roomID: "room-1",
                uploadID: "upload-cancel",
                clientMutationID: "mutation-cancel",
                onReservation: { _ in },
                onProgress: { _ in }
            )
            Issue.record("예약 이후 전송 실패가 성공하면 안 됩니다.")
        } catch {
            #expect(sendingRepository.cancelCallCount == 1)
            #expect(sendingRepository.finalizeCallCount == 4)
            #expect(uploader.uploadedSourceIndexes.count == 4)
            #expect(ChatMediaTransportFailurePolicy.isTransient(error))
        }

        try? FileManager.default.removeItem(at: pair.originalFileURL)
    }

    @Test func cancelReadyRaceReturnsReadySnapshotInsteadOfLocalFailure() async throws {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let uploader = ChatMediaForegroundUploaderFake()
        uploader.uploadError = TestError.unimplemented
        let sha256 = String(repeating: "d", count: 64)
        let pair = try makeProcessedImage(sha256: sha256)
        sendingRepository.reserveResult = ChatMediaUploadReservation(
            uploadID: "upload-ready",
            clientMutationID: "mutation-ready",
            processingStatus: .uploading,
            targets: [ChatMediaUploadTarget(
                attachmentID: "attachment-ready",
                sourceIndex: 0,
                path: "room/user/upload/attachment-ready/source",
                signedURL: URL(string: "https://storage.example/signed-put")!,
                requiredHeaders: ["content-type": "image/jpeg"],
                contentType: "image/jpeg",
                sizeBytes: 3,
                sha256: sha256
            )],
            expiresAt: Date().addingTimeInterval(86_400)
        )
        sendingRepository.cancelResult = ChatMediaProcessingSnapshot(
            uploadID: "upload-ready",
            processingStatus: .ready,
            messageID: "upload-ready",
            seq: 23,
            retryable: false,
            failureCode: nil
        )
        let useCase = makeUseCase(
            sendingRepository: sendingRepository,
            foregroundUploader: uploader
        )

        let snapshot = try await useCase.enqueueImageProcessing(
            pairs: [pair],
            roomID: "room-1",
            uploadID: "upload-ready",
            clientMutationID: "mutation-ready",
            onReservation: { _ in },
            onProgress: { _ in }
        )

        #expect(snapshot.processingStatus == .ready)
        #expect(snapshot.seq == 23)
        #expect(sendingRepository.cancelCallCount == 1)
        try? FileManager.default.removeItem(at: pair.originalFileURL)
    }

    @Test func activeUploadLimitRetriesSameIdentityWithConfiguredBackoff() async throws {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let delayRecorder = DelayRecorder()
        let pair = try makeProcessedImage(sha256: String(repeating: "e", count: 64))
        let reservation = ChatMediaUploadReservation(
            uploadID: "upload-retry",
            clientMutationID: "mutation-retry",
            processingStatus: .uploading,
            targets: [],
            expiresAt: Date().addingTimeInterval(86_400)
        )
        sendingRepository.reserveOutcomes = [
            .failure(ChatMediaUploadReservationError.activeUploadLimit),
            .failure(ChatMediaUploadReservationError.activeUploadLimit),
            .success(reservation)
        ]
        sendingRepository.refreshResult = reservation
        sendingRepository.finalizeResult = ChatMediaProcessingSnapshot(
            uploadID: "upload-retry",
            processingStatus: .queued,
            messageID: nil,
            seq: nil,
            retryable: true,
            failureCode: nil
        )
        let useCase = makeUseCase(
            sendingRepository: sendingRepository,
            slotRetryDelays: [2, 4, 8],
            sleep: { seconds in await delayRecorder.append(seconds) }
        )

        let snapshot = try await useCase.enqueueImageProcessing(
            pairs: [pair],
            roomID: "room-1",
            uploadID: "upload-retry",
            clientMutationID: "mutation-retry",
            onReservation: { _ in },
            onProgress: { _ in }
        )
        await useCase.finishImageUploadTurn(uploadID: "upload-retry")

        #expect(snapshot.processingStatus == .queued)
        #expect(sendingRepository.reserveCalls.map(\.uploadID) == [
            "upload-retry", "upload-retry", "upload-retry"
        ])
        #expect(sendingRepository.reserveCalls.map(\.clientMutationID) == [
            "mutation-retry", "mutation-retry", "mutation-retry"
        ])
        #expect(await delayRecorder.values() == [2, 4])
        try? FileManager.default.removeItem(at: pair.originalFileURL)
    }

    @Test func nonCapacityReservationErrorFailsWithoutBackoff() async throws {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let delayRecorder = DelayRecorder()
        let pair = try makeProcessedImage(sha256: String(repeating: "f", count: 64))
        sendingRepository.reserveOutcomes = [.failure(TestError.unimplemented)]
        let useCase = makeUseCase(
            sendingRepository: sendingRepository,
            sleep: { seconds in await delayRecorder.append(seconds) }
        )

        do {
            _ = try await useCase.enqueueImageProcessing(
                pairs: [pair],
                roomID: "room-1",
                uploadID: "upload-failure",
                clientMutationID: "mutation-failure",
                onReservation: { _ in },
                onProgress: { _ in }
            )
            Issue.record("용량 제한이 아닌 예약 오류는 즉시 실패해야 합니다.")
        } catch {
            #expect(sendingRepository.reserveCalls.count == 1)
            #expect(await delayRecorder.values().isEmpty)
        }

        try? FileManager.default.removeItem(at: pair.originalFileURL)
    }

    @Test func restoredUploadingSessionResumesWhenServerAdvancesWithoutReupload() async {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let uploader = ChatMediaForegroundUploaderFake()
        let delayRecorder = DelayRecorder()
        sendingRepository.statusOutcomes = [
            .success(makeProcessingSnapshot(status: .uploading)),
            .success(makeProcessingSnapshot(status: .queued))
        ]
        let useCase = makeUseCase(
            sendingRepository: sendingRepository,
            foregroundUploader: uploader,
            restoreStatusRetryDelays: [2, 4, 8],
            sleep: { seconds in await delayRecorder.append(seconds) }
        )

        let result = await useCase.reconcileRestoredMediaProcessing(
            roomID: "room-1",
            uploadID: "upload-restore",
            clientMutationID: "mutation-restore"
        )

        #expect(result == .resume(makeProcessingSnapshot(status: .queued)))
        #expect(sendingRepository.statusCallCount == 2)
        #expect(sendingRepository.cancelCallCount == 0)
        #expect(await delayRecorder.values() == [2])
        #expect(uploader.uploadedSourceIndexes.isEmpty)
    }

    @Test func restoredUploadingSessionHonorsReadyResultFromCancelRace() async {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let delayRecorder = DelayRecorder()
        sendingRepository.statusOutcomes = Array(
            repeating: .success(makeProcessingSnapshot(status: .uploading)),
            count: 4
        )
        sendingRepository.cancelResult = makeProcessingSnapshot(status: .ready)
        let useCase = makeUseCase(
            sendingRepository: sendingRepository,
            restoreStatusRetryDelays: [2, 4, 8],
            sleep: { seconds in await delayRecorder.append(seconds) }
        )

        let result = await useCase.reconcileRestoredMediaProcessing(
            roomID: "room-1",
            uploadID: "upload-restore",
            clientMutationID: "mutation-restore"
        )

        #expect(result == .resume(makeProcessingSnapshot(status: .ready)))
        #expect(sendingRepository.cancelCallCount == 1)
        #expect(await delayRecorder.values() == [2, 4, 8])
    }

    @Test func restoredUploadingSessionBecomesManualRetryAfterReconciliationExhaustion() async {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let delayRecorder = DelayRecorder()
        sendingRepository.statusOutcomes = Array(
            repeating: .success(makeProcessingSnapshot(status: .uploading)),
            count: 4
        )
        sendingRepository.cancelResult = makeProcessingSnapshot(status: .canceled)
        let useCase = makeUseCase(
            sendingRepository: sendingRepository,
            restoreStatusRetryDelays: [2, 4, 8],
            sleep: { seconds in await delayRecorder.append(seconds) }
        )

        let result = await useCase.reconcileRestoredMediaProcessing(
            roomID: "room-1",
            uploadID: "upload-restore",
            clientMutationID: "mutation-restore"
        )

        #expect(result == .manualRetry)
        #expect(sendingRepository.statusCallCount == 4)
        #expect(sendingRepository.cancelCallCount == 1)
        #expect(await delayRecorder.values() == [2, 4, 8])
    }

    @Test func restoredStatusErrorsNeverRestartForegroundUpload() async {
        let sendingRepository = ChatMediaMessageSendingRepositorySpy()
        let uploader = ChatMediaForegroundUploaderFake()
        sendingRepository.statusOutcomes = Array(repeating: .failure(TestError.unimplemented), count: 4)
        let useCase = makeUseCase(
            sendingRepository: sendingRepository,
            foregroundUploader: uploader,
            restoreStatusRetryDelays: [2, 4, 8]
        )

        let result = await useCase.reconcileRestoredMediaProcessing(
            roomID: "room-1",
            uploadID: "upload-restore",
            clientMutationID: "mutation-restore"
        )

        #expect(result == .manualRetry)
        #expect(sendingRepository.statusCallCount == 4)
        #expect(sendingRepository.cancelCallCount == 1)
        #expect(uploader.uploadedSourceIndexes.isEmpty)
    }

    @Test func nextBatchAndManualRetryWaitForExplicitTerminalRelease() async throws {
        let repository = ChatMediaMessageSendingRepositorySpy()
        let pair = try makeProcessedImage()
        defer { try? FileManager.default.removeItem(at: pair.originalFileURL) }
        let reservation = ChatMediaUploadReservation(uploadID: "first", clientMutationID: "mutation",
            processingStatus: .uploading, targets: [], expiresAt: Date().addingTimeInterval(1000))
        repository.reserveOutcomes = [.success(reservation), .failure(TestError.unimplemented),
            .success(reservation), .success(reservation)]
        repository.finalizeResult = makeProcessingSnapshot(status: .queued)
        let turns = ChatMediaUploadTurnQueue()
        let useCase = makeUseCase(sendingRepository: repository, uploadTurnQueue: turns)
        func enqueue(_ id: String) async throws -> ChatMediaProcessingSnapshot {
            try await useCase.enqueueImageProcessing(pairs: [pair], roomID: "room", uploadID: id,
                clientMutationID: id, onReservation: { _ in }, onProgress: { _ in })
        }
        _ = try await enqueue("first")
        let second = Task { try await enqueue("second") }
        for _ in 0..<2000 {
            if await turns.snapshot(lane: .images).waitingUploadIDs.count == 1 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let third = Task { try await enqueue("third") }
        for _ in 0..<2000 {
            if await turns.snapshot(lane: .images).waitingUploadIDs.count == 2 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(repository.reserveCalls.map(\.uploadID) == ["first"])
        await useCase.finishImageUploadTurn(uploadID: "first")
        do { _ = try await second.value; Issue.record("두 번째 묶음은 실패해야 한다") } catch { }
        #expect(await turns.snapshot(lane: .images).activeUploadIDs == ["second"])
        let retry = Task { try await enqueue("retry") }
        for _ in 0..<2000 {
            if await turns.snapshot(lane: .images).waitingUploadIDs.count == 2 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(await turns.snapshot(lane: .images).waitingUploadIDs == ["third", "retry"])
        await useCase.finishImageUploadTurn(uploadID: "second")
        _ = try await third.value
        #expect(repository.reserveCalls.map(\.uploadID) == ["first", "second", "third"])
        await useCase.finishImageUploadTurn(uploadID: "third")
        _ = try await retry.value
        await useCase.finishImageUploadTurn(uploadID: "retry")
        #expect(repository.reserveCalls.map(\.uploadID) == ["first", "second", "third", "retry"])
    }

    @Test func filesInsideBatchRunAtMostFourAtOnceBeforeFinalize() async throws {
        let repository = ChatMediaMessageSendingRepositorySpy()
        let pairs = try (0..<9).map { try makeProcessedImage(index: $0) }
        defer { pairs.forEach { try? FileManager.default.removeItem(at: $0.originalFileURL) } }
        let targets = pairs.flatMap { pair in
            (0..<2).map { role in
                ChatMediaUploadTarget(attachmentID: "a\(pair.index)", sourceIndex: pair.index * 2 + role,
                    path: "test/\(pair.index)/\(role)", signedURL: URL(string: "https://storage.example/put")!,
                    requiredHeaders: [:], contentType: "image/jpeg", sizeBytes: 3, sha256: "")
            }
        }
        repository.reserveResult = ChatMediaUploadReservation(uploadID: "batch", clientMutationID: "mutation",
            processingStatus: .uploading, targets: targets, expiresAt: Date().addingTimeInterval(1000))
        repository.finalizeResult = makeProcessingSnapshot(status: .queued)
        let uploader = GatedBatchUploader()
        let useCase = makeUseCase(sendingRepository: repository, foregroundUploader: uploader)
        let task = Task { try await useCase.enqueueImageProcessing(pairs: pairs, roomID: "room",
            uploadID: "batch", clientMutationID: "mutation", onReservation: { _ in }, onProgress: { _ in }) }
        for _ in 0..<2000 {
            if await uploader.startedCount == 4 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(await uploader.startedCount == 4)
        #expect(repository.finalizeCallCount == 0)
        await uploader.open()
        _ = try await task.value
        #expect(await uploader.peak == 4)
        #expect(await uploader.startedCount == 18)
        #expect(repository.finalizeCallCount == 1)
        await useCase.finishImageUploadTurn(uploadID: "batch")
    }

    private func makeUseCase(
        imageRepository: FirebaseImageStorageRepositoryFake = FirebaseImageStorageRepositoryFake(),
        videoRepository: FirebaseVideoStorageRepositoryFake = FirebaseVideoStorageRepositoryFake(),
        sendingRepository: ChatMediaMessageSendingRepositorySpy = ChatMediaMessageSendingRepositorySpy(),
        foregroundUploader: ChatMediaForegroundUploading = ChatMediaForegroundUploaderFake(),
        attachmentImageLoader: ChatAttachmentImageLoading = ChatAttachmentImageLoaderSpy(),
        previewDirectory: URL? = nil,
        uploadTurnQueue: ChatMediaUploadTurnQueueProtocol = ChatMediaUploadTurnQueue(),
        slotRetryDelays: [UInt64] = [2, 4, 8, 15, 30],
        restoreStatusRetryDelays: [UInt64] = [2, 4, 8],
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { _ in }
    ) -> ChatMediaUploadUseCase {
        ChatMediaUploadUseCase(
            imageStorageRepository: imageRepository,
            videoStorageRepository: videoRepository,
            sendingRepository: sendingRepository,
            foregroundUploader: foregroundUploader,
            attachmentImageLoader: attachmentImageLoader,
            currentUserProvider: {
                ChatMessageSenderSnapshot(
                    senderUID: "me@example.com",
                    senderNickname: "나",
                    senderAvatarPath: "avatars/me.jpg"
                )
            },
            dateProvider: { Date(timeIntervalSince1970: 123) },
            previewDirectoryProvider: { previewDirectory ?? FileManager.default.temporaryDirectory },
            fileManager: .default,
            uploadTurnQueue: uploadTurnQueue,
            slotRetryDelays: slotRetryDelays,
            restoreStatusRetryDelays: restoreStatusRetryDelays,
            sleep: sleep
        )
    }

    private func makeProcessingSnapshot(
        status: ChatMediaServerProcessingStatus
    ) -> ChatMediaProcessingSnapshot {
        ChatMediaProcessingSnapshot(
            uploadID: "upload-restore",
            processingStatus: status,
            messageID: status == .ready ? "upload-restore" : nil,
            seq: status == .ready ? 24 : nil,
            retryable: status != .ready,
            failureCode: nil
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
    struct ReserveCall {
        let roomID: String
        let uploadID: String
        let clientMutationID: String
        let kind: String
    }

    struct PreflightCall: Equatable {
        let roomID: String
        let messageID: String
        let kind: String
        let attachmentCount: Int
        let expectedPathCount: Int
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
        let senderUID: String
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
    var reserveResult: ChatMediaUploadReservation?
    var reserveOutcomes: [Result<ChatMediaUploadReservation, Error>] = []
    var refreshResult: ChatMediaUploadReservation?
    var finalizeResult: ChatMediaProcessingSnapshot?
    var finalizeError: Error?
    var finalizeOutcomes: [Result<ChatMediaProcessingSnapshot, Error>] = []
    var cancelResult: ChatMediaProcessingSnapshot?
    var statusOutcomes: [Result<ChatMediaProcessingSnapshot, Error>] = []
    private(set) var refreshCallCount = 0
    private(set) var finalizeCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var statusCallCount = 0
    private(set) var reserveCalls: [ReserveCall] = []

    func reserveMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String,
        sources: [ChatMediaSourceDescriptor]
    ) async throws -> ChatMediaUploadReservation {
        reserveCalls.append(ReserveCall(
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID,
            kind: kind
        ))
        if !reserveOutcomes.isEmpty {
            return try reserveOutcomes.removeFirst().get()
        }
        guard let reserveResult else { throw TestError.unimplemented }
        return reserveResult
    }

    func refreshMediaUploadTargets(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaUploadReservation {
        refreshCallCount += 1
        guard let refreshResult else { throw TestError.unimplemented }
        return refreshResult
    }

    func finalizeMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String
    ) async throws -> ChatMediaProcessingSnapshot {
        finalizeCallCount += 1
        if !finalizeOutcomes.isEmpty { return try finalizeOutcomes.removeFirst().get() }
        if let finalizeError { throw finalizeError }
        guard let finalizeResult else { throw TestError.unimplemented }
        return finalizeResult
    }

    func cancelMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot {
        cancelCallCount += 1
        guard let cancelResult else { throw TestError.unimplemented }
        return cancelResult
    }

    func mediaProcessingStatus(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot {
        statusCallCount += 1
        guard !statusOutcomes.isEmpty else { throw TestError.unimplemented }
        return try statusOutcomes.removeFirst().get()
    }

    func preflightMediaUpload(
        roomID: String,
        messageID: String,
        kind: String,
        attachmentCount: Int,
        expectedPathCount: Int
    ) async throws {
        preflightCalls.append(PreflightCall(
            roomID: roomID,
            messageID: messageID,
            kind: kind,
            attachmentCount: attachmentCount,
            expectedPathCount: expectedPathCount
        ))
        if let preflightError {
            throw preflightError
        }
    }

    func sendImages(
        _ room: ChatRoom,
        attachments: [ChatAttachment],
        senderAvatarPath: String?,
        clientMessageID: String?
    ) async throws -> ChatMessageSendReceipt {
        imageCalls.append(ImageCall(
            room: room,
            attachments: attachments,
            senderAvatarPath: senderAvatarPath,
            clientMessageID: clientMessageID
        ))
        return ChatMessageSendReceipt(
            roomID: room.id,
            messageID: clientMessageID ?? "image-message",
            seq: 42
        )
    }

    func sendVideo(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?
    ) async throws -> ChatMessageSendReceipt {
        videoCalls.append(VideoCall(
            roomID: roomID,
            payload: payload,
            senderAvatarPath: senderAvatarPath
        ))
        return ChatMessageSendReceipt(roomID: roomID, messageID: payload.messageID, seq: 42)
    }

    func sendFailedVideo(
        roomID: String,
        senderUID: String,
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
            senderUID: senderUID,
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

private actor GatedBatchUploader: ChatMediaForegroundUploading {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var active = 0
    private(set) var peak = 0
    private(set) var startedCount = 0
    func upload(source: ChatMediaSourceDescriptor, target: ChatMediaUploadTarget,
        onProgress: @escaping @Sendable (Double) -> Void) async throws -> ChatMediaUploadedSource {
        active += 1
        startedCount += 1
        peak = max(peak, active)
        if !isOpen { await withCheckedContinuation { waiters.append($0) } }
        active -= 1
        onProgress(1)
        return .init(attachmentID: target.attachmentID, sourceIndex: target.sourceIndex,
            path: target.path, sizeBytes: target.sizeBytes)
    }
    func open() {
        isOpen = true
        let values = waiters
        waiters.removeAll()
        values.forEach { $0.resume() }
    }
}

private final class ChatMediaForegroundUploaderFake: ChatMediaForegroundUploading {
    var uploadError: Error?
    private(set) var uploadedSourceIndexes: [Int] = []

    func upload(
        source: ChatMediaSourceDescriptor,
        target: ChatMediaUploadTarget,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ChatMediaUploadedSource {
        uploadedSourceIndexes.append(target.sourceIndex)
        if let uploadError { throw uploadError }
        onProgress(1)
        return ChatMediaUploadedSource(
            attachmentID: target.attachmentID,
            sourceIndex: target.sourceIndex,
            path: target.path,
            sizeBytes: target.sizeBytes
        )
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

private actor DelayRecorder {
    private var recordedValues: [UInt64] = []

    func append(_ value: UInt64) {
        recordedValues.append(value)
    }

    func values() -> [UInt64] {
        recordedValues
    }
}
