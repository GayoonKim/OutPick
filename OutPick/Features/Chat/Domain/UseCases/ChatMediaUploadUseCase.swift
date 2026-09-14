//
//  ChatMediaUploadUseCase.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

enum ChatMediaUploadError: Error {
    case emptyImageAttachments
    case invalidUploadContract
    case uploadRetryLimitExceeded
    case uploadIncomplete
}

protocol ChatMediaUploadUseCaseProtocol {
    func beginProcessingBatch(uploadID: String) async throws
    func registerProcessingBatches(uploadIDs: [String]) async
    func confirmedMessage(roomID: String, messageID: String) async throws -> ChatMessage?
    func enqueueImageProcessing(
        pairs: [ProcessedImage],
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        onWaitingForSlot: @escaping () async -> Void,
        onReservation: @escaping (ChatMediaUploadReservation) async -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> ChatMediaProcessingSnapshot

    func enqueueVideoProcessing(
        prepared: PreparedVideo,
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        onWaitingForSlot: @escaping () async -> Void,
        onReservation: @escaping (ChatMediaUploadReservation) async -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> ChatMediaProcessingSnapshot

    func mediaProcessingStatus(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot

    func cancelMediaProcessing(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot

    func reconcileRestoredMediaProcessing(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async -> ChatMediaRestoreReconciliationResult

    func makePendingImageMessage(
        roomID: String,
        messageID: String,
        pairs: [ProcessedImage]
    ) -> ChatMessage?

    func makePendingVideoMessage(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo
    ) -> ChatMessage?

    func uploadPendingImages(
        pairs: [ProcessedImage],
        roomID: String,
        messageID: String,
        onProgress: ((Double) -> Void)?
    ) async throws -> [Attachment]

    func sendUploadedImages(
        room: ChatRoom,
        attachments: [Attachment],
        clientMessageID: String,
        ensureReservation: Bool
    ) async throws -> ChatMessageSendReceipt

    func cacheFailedImageThumbnails(_ pairs: [ProcessedImage]) async
    func cleanupImageOriginalFiles(_ pairs: [ProcessedImage])
    func cleanupReplacedLocalPreviewFiles(previous: ChatMessage, next: ChatMessage)

    func uploadVideo(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo,
        onProgress: @escaping (Double) -> Void
    ) async throws -> VideoMetaPayload

    func sendUploadedVideo(
        roomID: String,
        payload: VideoMetaPayload,
        ensureReservation: Bool
    ) async throws -> ChatMessageSendReceipt
    func sendFailedVideo(roomID: String, prepared: PreparedVideo)

    func finishImageUploadTurn(uploadID: String) async
    func finishVideoUploadTurn(uploadID: String) async
}

extension ChatMediaUploadUseCaseProtocol {
    func beginProcessingBatch(uploadID: String) async throws {}
    func registerProcessingBatches(uploadIDs: [String]) async {}
    func confirmedMessage(roomID: String, messageID: String) async throws -> ChatMessage? { nil }

    func enqueueImageProcessing(
        pairs: [ProcessedImage],
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        onReservation: @escaping (ChatMediaUploadReservation) async -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> ChatMediaProcessingSnapshot {
        try await enqueueImageProcessing(
            pairs: pairs,
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID,
            onWaitingForSlot: {},
            onReservation: onReservation,
            onProgress: onProgress
        )
    }

    func enqueueVideoProcessing(
        prepared: PreparedVideo,
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        onReservation: @escaping (ChatMediaUploadReservation) async -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> ChatMediaProcessingSnapshot {
        try await enqueueVideoProcessing(
            prepared: prepared,
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID,
            onWaitingForSlot: {},
            onReservation: onReservation,
            onProgress: onProgress
        )
    }
}

final class ChatMediaUploadUseCase: ChatMediaUploadUseCaseProtocol {
    private let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    private let messageRepository: FirebaseMessageRepositoryProtocol?
    private let videoStorageRepository: FirebaseVideoStorageRepositoryProtocol
    private let sendingRepository: ChatMediaMessageSendingRepositoryProtocol
    private let foregroundUploader: ChatMediaForegroundUploading
    private let attachmentImageLoader: ChatAttachmentImageLoading
    private let currentUserProvider: () -> ChatMessageSenderSnapshot
    private let dateProvider: () -> Date
    private let previewDirectoryProvider: () -> URL?
    private let fileManager: FileManager
    private let uploadTurnQueue: ChatMediaUploadTurnQueueProtocol
    private let filesPerBatch: Int
    private let slotRetryDelays: [UInt64]
    private let restoreStatusRetryDelays: [UInt64]
    private let sleep: @Sendable (UInt64) async throws -> Void

    func confirmedMessage(roomID: String, messageID: String) async throws -> ChatMessage? {
        guard let messageRepository else { throw ChatMediaUploadError.invalidUploadContract }
        return try await messageRepository.fetchConfirmedMessage(roomID: roomID, messageID: messageID)
    }

    init(
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        videoStorageRepository: FirebaseVideoStorageRepositoryProtocol,
        messageRepository: FirebaseMessageRepositoryProtocol? = nil,
        sendingRepository: ChatMediaMessageSendingRepositoryProtocol = SocketChatMediaMessageSendingRepository(),
        foregroundUploader: ChatMediaForegroundUploading = URLSessionChatMediaForegroundUploader(),
        attachmentImageLoader: ChatAttachmentImageLoading,
        currentUserProvider: @escaping () -> ChatMessageSenderSnapshot = {
            ChatMessageSenderSnapshot(
                senderUID: LoginManager.shared.canonicalUserID,
                senderNickname: "",
                senderAvatarPath: nil
            )
        },
        dateProvider: @escaping () -> Date = { Date() },
        previewDirectoryProvider: @escaping () -> URL? = {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        },
        fileManager: FileManager = .default,
        uploadTurnQueue: ChatMediaUploadTurnQueueProtocol = ChatMediaUploadTurnQueue(),
        filesPerBatch: Int = 4,
        slotRetryDelays: [UInt64] = [2, 4, 8, 15, 30],
        restoreStatusRetryDelays: [UInt64] = [2, 4, 8],
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
        }
    ) {
        self.imageStorageRepository = imageStorageRepository
        self.messageRepository = messageRepository
        self.videoStorageRepository = videoStorageRepository
        self.sendingRepository = sendingRepository
        self.foregroundUploader = foregroundUploader
        self.attachmentImageLoader = attachmentImageLoader
        self.currentUserProvider = currentUserProvider
        self.dateProvider = dateProvider
        self.previewDirectoryProvider = previewDirectoryProvider
        self.fileManager = fileManager
        self.uploadTurnQueue = uploadTurnQueue
        precondition(filesPerBatch > 0)
        self.filesPerBatch = filesPerBatch
        self.slotRetryDelays = slotRetryDelays
        self.restoreStatusRetryDelays = restoreStatusRetryDelays
        self.sleep = sleep
    }

    func enqueueImageProcessing(
        pairs: [ProcessedImage],
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        onWaitingForSlot: @escaping () async -> Void,
        onReservation: @escaping (ChatMediaUploadReservation) async -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> ChatMediaProcessingSnapshot {
        var transientThumbnails: [URL] = []
        defer { transientThumbnails.forEach { try? fileManager.removeItem(at: $0) } }
        let sources = try pairs.sorted(by: { $0.index < $1.index }).flatMap { pair -> [ChatMediaSourceDescriptor] in
            let thumb: URL
            if let file = pair.thumbFileURL { thumb = file }
            else {
                thumb = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try pair.thumbData.write(to: thumb)
                transientThumbnails.append(thumb)
            }
            let thumbBytes = try fileManager.attributesOfItem(atPath: thumb.path)[.size] as? NSNumber
            return [
                ChatMediaSourceDescriptor(index: pair.index * 2, fileURL: pair.originalFileURL,
                    contentType: pair.contentType, sizeBytes: Int64(pair.bytesOriginal), sha256: pair.sha256,
                    mediaFormat: pair.mediaFormat, isAnimated: pair.isAnimated, attachmentIndex: pair.index,
                    width: pair.originalWidth, height: pair.originalHeight),
                ChatMediaSourceDescriptor(index: pair.index * 2 + 1, fileURL: thumb,
                    contentType: "image/jpeg", sizeBytes: thumbBytes?.int64Value ?? 0, sha256: "",
                    mediaFormat: "jpeg", isAnimated: false, role: "thumbnail", attachmentIndex: pair.index,
                    width: pair.originalWidth, height: pair.originalHeight)
            ]
        }
        try await uploadTurnQueue.acquire(lane: .images, uploadID: uploadID)
        do {
            try Task.checkCancellation()
            await onWaitingForSlot()
            let result = try await enqueueProcessing(
                sources: sources,
                roomID: roomID,
                uploadID: uploadID,
                clientMutationID: clientMutationID,
                kind: "images",
                onWaitingForSlot: onWaitingForSlot,
                onReservation: onReservation,
                onProgress: onProgress
            )
            return result
        } catch {
            // 성공 메시지 반영 또는 실패 UI 처리 후 호출자가 실행권을 반환한다.
            throw error
        }
    }

    func enqueueVideoProcessing(
        prepared: PreparedVideo,
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        onWaitingForSlot: @escaping () async -> Void,
        onReservation: @escaping (ChatMediaUploadReservation) async -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> ChatMediaProcessingSnapshot {
        let source = ChatMediaSourceDescriptor(
            index: 0,
            fileURL: prepared.compressedFileURL,
            contentType: "video/mp4",
            sizeBytes: prepared.sizeBytes,
            sha256: prepared.sha256,
            mediaFormat: "mp4",
            isAnimated: false,
            width: prepared.width, height: prepared.height, duration: prepared.duration
        )
        let thumb: URL
        if let file = prepared.thumbnailFileURL { thumb = file }
        else {
            thumb = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try prepared.thumbnailData.write(to: thumb)
        }
        defer { if prepared.thumbnailFileURL == nil { try? fileManager.removeItem(at: thumb) } }
        let thumbBytes = try fileManager.attributesOfItem(atPath: thumb.path)[.size] as? NSNumber
        let thumbnail = ChatMediaSourceDescriptor(index: 1, fileURL: thumb, contentType: "image/jpeg",
            sizeBytes: thumbBytes?.int64Value ?? 0, sha256: "", mediaFormat: "jpeg", isAnimated: false,
            role: "thumbnail", attachmentIndex: 0, width: prepared.width, height: prepared.height)
        try await uploadTurnQueue.acquire(lane: .images, uploadID: uploadID)
        do {
            try Task.checkCancellation()
            await onWaitingForSlot()
            let result = try await enqueueProcessing(
                sources: [source, thumbnail],
                roomID: roomID,
                uploadID: uploadID,
                clientMutationID: clientMutationID,
                kind: "video",
                onWaitingForSlot: onWaitingForSlot,
                onReservation: onReservation,
                onProgress: onProgress
            )
            return result
        } catch {
            throw error
        }
    }

    func mediaProcessingStatus(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot {
        try await sendingRepository.mediaProcessingStatus(
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID
        )
    }

    func cancelMediaProcessing(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot {
        return try await sendingRepository.cancelMediaUpload(
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID
        )
    }

    func reconcileRestoredMediaProcessing(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async -> ChatMediaRestoreReconciliationResult {
        var retryIndex = 0
        while true {
            do {
                let snapshot = try await sendingRepository.mediaProcessingStatus(
                    roomID: roomID,
                    uploadID: uploadID,
                    clientMutationID: clientMutationID
                )
                switch snapshot.processingStatus {
                case .queued, .processing, .ready:
                    return .resume(snapshot)
                case .failed, .canceled, .expired:
                    return .manualRetry
                case .uploading:
                    break
                }
            } catch {
                // 재실행 복원에서는 파일을 자동 재업로드하지 않고 status만 제한적으로 재확인한다.
            }

            guard retryIndex < restoreStatusRetryDelays.count else {
                return await resolveRestoredUploadAfterStatusRetries(
                    roomID: roomID,
                    uploadID: uploadID,
                    clientMutationID: clientMutationID
                )
            }
            let delay = restoreStatusRetryDelays[retryIndex]
            retryIndex += 1
            do {
                try await sleep(delay)
                try Task.checkCancellation()
            } catch {
                return .manualRetry
            }
        }
    }

    private func resolveRestoredUploadAfterStatusRetries(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async -> ChatMediaRestoreReconciliationResult {
        guard let snapshot = try? await sendingRepository.cancelMediaUpload(
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID
        ) else {
            return .manualRetry
        }
        switch snapshot.processingStatus {
        case .queued, .processing, .ready:
            return .resume(snapshot)
        case .uploading, .failed, .canceled, .expired:
            return .manualRetry
        }
    }

    private func enqueueProcessing(
        sources: [ChatMediaSourceDescriptor],
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String,
        onWaitingForSlot: @escaping () async -> Void,
        onReservation: @escaping (ChatMediaUploadReservation) async -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> ChatMediaProcessingSnapshot {
        let orderedSources = sources.sorted(by: { $0.index < $1.index })
        #if DEBUG
        print("[MediaQA] event=batch_reservation_started messageID=\(uploadID) files=\(sources.count) bytes=\(sources.reduce(Int64(0)) { $0 + $1.sizeBytes }) uptime=\(ProcessInfo.processInfo.systemUptime)")
        #endif
        var retryIndex = 0
        let reservation: ChatMediaUploadReservation
        while true {
            do {
                reservation = try await retryTransport { try await self.sendingRepository.reserveMediaUpload(
                    roomID: roomID,
                    uploadID: uploadID,
                    clientMutationID: clientMutationID,
                    kind: kind,
                    sources: orderedSources
                ) }
                break
            } catch ChatMediaUploadReservationError.activeUploadLimit {
                await onWaitingForSlot()
                let fallbackDelay = slotRetryDelays.last ?? 30
                let delay = slotRetryDelays.isEmpty
                    ? fallbackDelay
                    : slotRetryDelays[min(retryIndex, slotRetryDelays.count - 1)]
                retryIndex += 1
                try await sleep(delay)
                try Task.checkCancellation()
            }
        }
        await onReservation(reservation)
        #if DEBUG
        print("[MediaQA] event=batch_reserved messageID=\(uploadID) uptime=\(ProcessInfo.processInfo.systemUptime)")
        #endif

        do {
            try Task.checkCancellation()
            guard !orderedSources.isEmpty else { throw ChatMediaUploadError.invalidUploadContract }
            let sourcesByIndex = Dictionary(uniqueKeysWithValues: orderedSources.map { ($0.index, $0) })
            let totalBytes = orderedSources.reduce(0) { $0 + Int($1.sizeBytes) }

            var reconciliation = reservation
            var cycle = 0
            var lastUploadError: Error?
            while true {
                guard cycle < 4 else { throw lastUploadError ?? ChatMediaUploadError.uploadRetryLimitExceeded }
                cycle += 1
                let initialCompletedBytes = max(0, totalBytes - reconciliation.targets.reduce(0) { $0 + Int($1.sizeBytes) })
                let targets = reconciliation.targets
                let progress = ChatMediaBatchProgress(completed: initialCompletedBytes,
                    total: totalBytes, weights: targets.map { Int($0.sizeBytes) }, onProgress: onProgress)
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        var next = 0
                        func add(_ index: Int) {
                            let target = targets[index]
                            group.addTask { [foregroundUploader] in
                                try Task.checkCancellation()
                                guard let source = sourcesByIndex[target.sourceIndex],
                                      source.sizeBytes == target.sizeBytes,
                                      source.contentType == target.contentType else {
                                    throw ChatMediaUploadError.invalidUploadContract
                                }
                                _ = try await foregroundUploader.upload(source: source, target: target) { value in
                                    progress.update(index: index, fraction: value)
                                }
                                progress.update(index: index, fraction: 1)
                            }
                        }
                        while next < min(filesPerBatch, targets.count) { add(next); next += 1 }
                        while try await group.next() != nil {
                            if next < targets.count { add(next); next += 1 }
                        }
                    }
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    lastUploadError = error
                    // 진행 중 PUT이 모두 종료된 뒤 finalize로 응답 유실/실제 누락을 구분한다.
                }
                do {
                    #if DEBUG
                    print("[MediaQA] event=batch_finalize_started messageID=\(uploadID) uptime=\(ProcessInfo.processInfo.systemUptime)")
                    #endif
                    let snapshot = try await retryTransport { try await self.sendingRepository.finalizeMediaUpload(
                        roomID: roomID,
                        uploadID: uploadID,
                        clientMutationID: clientMutationID,
                        kind: kind
                    ) }
                    onProgress(1)
                    return snapshot
                } catch ChatMediaUploadError.uploadIncomplete {
                    // 서버가 누락을 확인한 경우에만 재개 대상을 조회한다.
                }
                reconciliation = try await retryTransport { try await self.sendingRepository.refreshMediaUploadTargets(
                    roomID: roomID,
                    uploadID: uploadID,
                    clientMutationID: clientMutationID
                ) }
            }
        } catch {
            // 예약 이후의 로컬/전송 실패는 server slot과 source를 즉시 정리한다.
            // cancel/ready 경합에서 ready가 이기면 실패 버블로 만들지 않고 그대로 수렴한다.
            if let canceled = try? await sendingRepository.cancelMediaUpload(
                roomID: roomID,
                uploadID: uploadID,
                clientMutationID: clientMutationID
            ), canceled.processingStatus == .ready {
                return canceled
            }
            throw error
        }
    }

    func finishImageUploadTurn(uploadID: String) async {
        await uploadTurnQueue.release(lane: .images, uploadID: uploadID)
    }

    func registerProcessingBatches(uploadIDs: [String]) async {
        await uploadTurnQueue.register(lane: .images, uploadIDs: uploadIDs)
    }

    func beginProcessingBatch(uploadID: String) async throws {
        try await uploadTurnQueue.acquire(lane: .images, uploadID: uploadID)
    }

    private func retryTransport<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do { return try await operation() }
            catch {
                guard ChatMediaTransportFailurePolicy.isTransient(error), attempt < 2 else { throw error }
                attempt += 1
                try await sleep(UInt64(attempt))
            }
        }
    }

    func finishVideoUploadTurn(uploadID: String) async {
        await uploadTurnQueue.release(lane: .images, uploadID: uploadID)
    }

    func makePendingImageMessage(
        roomID: String,
        messageID: String,
        pairs: [ProcessedImage]
    ) -> ChatMessage? {
        guard !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let attachments = makePendingImagePreviewAttachments(messageID: messageID, pairs: pairs)
        guard !attachments.isEmpty else { return nil }

        let sender = currentUserProvider()
        return ChatMessage(
            ID: messageID,
            seq: 0,
            roomID: roomID,
            senderUID: sender.senderUID,
            senderNickname: sender.senderNickname,
            senderAvatarPath: sender.senderAvatarPath,
            msg: "",
            sentAt: dateProvider(),
            attachments: attachments,
            replyPreview: nil,
            isFailed: false
        )
    }

    func makePendingVideoMessage(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo
    ) -> ChatMessage? {
        guard !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let attachment = makePendingVideoPreviewAttachment(messageID: messageID, prepared: prepared) else {
            return nil
        }

        let sender = currentUserProvider()
        return ChatMessage(
            ID: messageID,
            seq: 0,
            roomID: roomID,
            senderUID: sender.senderUID,
            senderNickname: sender.senderNickname,
            senderAvatarPath: sender.senderAvatarPath,
            msg: "",
            sentAt: dateProvider(),
            attachments: [attachment],
            replyPreview: nil,
            isFailed: false
        )
    }

    func uploadPendingImages(
        pairs: [ProcessedImage],
        roomID: String,
        messageID: String,
        onProgress: ((Double) -> Void)?
    ) async throws -> [Attachment] {
        try await sendingRepository.preflightMediaUpload(
            roomID: roomID,
            messageID: messageID,
            kind: "images",
            attachmentCount: pairs.count,
            expectedPathCount: pairs.count * 2
        )
        let attachments = try await imageStorageRepository.uploadPairsToRoomMessage(
            pairs,
            roomID: roomID,
            messageID: messageID,
            cacheTTLThumbDays: 30,
            cacheTTLOriginalDays: 7,
            cleanupTemp: false,
            onProgress: onProgress
        )
        cleanupImageOriginalFiles(pairs)
        return attachments
    }

    func sendUploadedImages(
        room: ChatRoom,
        attachments: [Attachment],
        clientMessageID: String,
        ensureReservation: Bool = true
    ) async throws -> ChatMessageSendReceipt {
        guard !attachments.isEmpty else {
            throw ChatMediaUploadError.emptyImageAttachments
        }

        if ensureReservation {
            try await sendingRepository.preflightMediaUpload(
                roomID: room.id,
                messageID: clientMessageID,
                kind: "images",
                attachmentCount: attachments.count,
                expectedPathCount: attachments.count * 2
            )
        }
        
        return try await sendingRepository.sendImages(
            room,
            attachments: attachments,
            senderAvatarPath: currentUserProvider().senderAvatarPath,
            clientMessageID: clientMessageID
        )
    }

    func cacheFailedImageThumbnails(_ pairs: [ProcessedImage]) async {
        for pair in pairs {
            await attachmentImageLoader.storeOutgoingPreview(data: pair.thumbData, forKey: pair.sha256)
        }
    }

    func cleanupImageOriginalFiles(_ pairs: [ProcessedImage]) {
        for pair in pairs {
            try? fileManager.removeItem(at: pair.originalFileURL)
        }
    }

    func cleanupReplacedLocalPreviewFiles(previous: ChatMessage, next: ChatMessage) {
        let newThumbPaths = Set(next.attachments.map(\.pathThumb))

        for oldPath in previous.attachments.map(\.pathThumb) {
            let isLocal = oldPath.hasPrefix("file://") || oldPath.hasPrefix("/")
            guard isLocal, !newThumbPaths.contains(oldPath) else { continue }

            let fileURL = oldPath.hasPrefix("file://") ? URL(string: oldPath) : URL(fileURLWithPath: oldPath)
            if let fileURL {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    func uploadVideo(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo,
        onProgress: @escaping (Double) -> Void
    ) async throws -> VideoMetaPayload {
        try await sendingRepository.preflightMediaUpload(
            roomID: roomID,
            messageID: messageID,
            kind: "video",
            attachmentCount: 1,
            expectedPathCount: 2
        )
        let videoPaths = ChatStoragePath.roomMessageVideo(roomID: roomID, messageID: messageID)

        if !prepared.thumbnailData.isEmpty {
            await attachmentImageLoader.storeOutgoingPreview(data: prepared.thumbnailData, forKey: prepared.sha256)
            print(#function, "ThumbCache video thumb saved: \(prepared.sha256)")
        }

        try await videoStorageRepository.putVideoFileToStorage(
            localURL: prepared.compressedFileURL,
            path: videoPaths.video,
            contentType: "video/mp4",
            onProgress: onProgress
        )

        if !prepared.thumbnailData.isEmpty {
            try await videoStorageRepository.putVideoDataToStorage(
                data: prepared.thumbnailData,
                path: videoPaths.thumb,
                contentType: "image/jpeg"
            )
        }

        return VideoMetaPayload(
            roomID: roomID,
            messageID: messageID,
            storagePath: videoPaths.video,
            thumbnailPath: videoPaths.thumb,
            duration: prepared.duration,
            width: prepared.width,
            height: prepared.height,
            sizeBytes: prepared.sizeBytes,
            approxBitrateMbps: prepared.approxBitrateMbps,
            preset: prepared.preset.chatPayloadCode
        )
    }

    func sendUploadedVideo(
        roomID: String,
        payload: VideoMetaPayload,
        ensureReservation: Bool = true
    ) async throws -> ChatMessageSendReceipt {
        if ensureReservation {
            try await sendingRepository.preflightMediaUpload(
                roomID: roomID,
                messageID: payload.messageID,
                kind: "video",
                attachmentCount: 1,
                expectedPathCount: 2
            )
        }
        return try await sendingRepository.sendVideo(
            roomID: roomID,
            payload: payload,
            senderAvatarPath: currentUserProvider().senderAvatarPath
        )
    }

    func sendFailedVideo(roomID: String, prepared: PreparedVideo) {
        let sender = currentUserProvider()
        sendingRepository.sendFailedVideo(
            roomID: roomID,
            senderUID: sender.senderUID,
            senderNickname: sender.senderNickname,
            localURL: prepared.compressedFileURL,
            thumbData: prepared.thumbnailData,
            duration: prepared.duration,
            width: prepared.width,
            height: prepared.height,
            presetCode: prepared.preset.chatPayloadCode
        )
    }

    private func makePendingImagePreviewAttachments(
        messageID: String,
        pairs: [ProcessedImage]
    ) -> [Attachment] {
        var attachments: [Attachment] = []
        attachments.reserveCapacity(pairs.count)

        for pair in pairs.sorted(by: { $0.index < $1.index }) {
            guard fileManager.fileExists(atPath: pair.originalFileURL.path) else { continue }
            let sourcePath = pair.originalFileURL.absoluteString
            attachments.append(Attachment(
                type: .image,
                index: pair.index,
                pathThumb: pair.thumbFileURL?.absoluteString ?? sourcePath,
                pathOriginal: sourcePath,
                width: pair.originalWidth,
                height: pair.originalHeight,
                bytesOriginal: pair.bytesOriginal,
                hash: pair.sha256,
                blurhash: nil,
                duration: nil,
                mediaFormat: pair.mediaFormat,
                isAnimated: pair.isAnimated
            ))
        }
        return attachments
    }

    private func makePendingVideoPreviewAttachment(
        messageID: String,
        prepared: PreparedVideo
    ) -> Attachment? {
        guard !prepared.thumbnailData.isEmpty else { return nil }
        guard let cachesDir = previewDirectoryProvider() else { return nil }
        let baseDir = cachesDir
            .appendingPathComponent("pending-video-preview", isDirectory: true)
            .appendingPathComponent(messageID, isDirectory: true)
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let fileURL = baseDir.appendingPathComponent("\(prepared.sha256).jpg")
        do {
            try prepared.thumbnailData.write(to: fileURL, options: .atomic)
            return Attachment(
                type: .video,
                index: 0,
                pathThumb: fileURL.absoluteString,
                pathOriginal: prepared.compressedFileURL.path,
                width: prepared.width,
                height: prepared.height,
                bytesOriginal: Int(prepared.sizeBytes),
                hash: prepared.sha256,
                blurhash: nil,
                duration: prepared.duration,
                approxBitrateMbps: prepared.approxBitrateMbps,
                preset: prepared.preset.chatPayloadCode
            )
        } catch {
            print("pending video preview write 실패: \(error)")
            return nil
        }
    }
}

extension VideoUploadPreset {
    var chatPayloadCode: String {
        switch self {
        case .standard720: return "standard720"
        case .dataSaver720: return "dataSaver720"
        case .high1080: return "high1080"
        }
    }
}
