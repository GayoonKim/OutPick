//
//  ChatOutgoingOutboxUseCase.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import Foundation

enum ChatOutgoingOutboxRetryPayload {
    case text(ChatMessage)
    case uploadImages(room: ChatRoom, messageID: String, pairs: [ProcessedImage])
    case finalizeImages(room: ChatRoom, messageID: String, attachments: [Attachment])
    case uploadVideo(roomID: String, messageID: String, prepared: PreparedVideo)
    case finalizeVideo(roomID: String, messageID: String, payload: VideoMetaPayload)
}

protocol ChatOutgoingOutboxUseCaseProtocol {
    func stageTextMessage(_ message: ChatMessage) async
    func stageImageMessage(_ message: ChatMessage, pairs: [ProcessedImage]) async
    func stageVideoMessage(_ message: ChatMessage, prepared: PreparedVideo) async
    func markImageUploadCompleted(messageID: String, attachments: [Attachment]) async
    func markVideoUploadCompleted(messageID: String, payload: VideoMetaPayload) async
    func markMediaReservation(messageID: String, reservation: ChatMediaUploadReservation) async
    func markMediaProcessing(messageID: String, snapshot: ChatMediaProcessingSnapshot) async
    func markMediaRestoreRequiresManualRetry(messageID: String) async
    func mediaSessionPayload(messageID: String) async -> ChatMediaUploadSessionPayload?
    func pendingMediaRecords(roomID: String) async -> [ChatOutgoingOutboxRecord]
    func markFailed(message: ChatMessage, error: Error?) async
    func retryPayload(for message: ChatMessage, room: ChatRoom) async -> ChatOutgoingOutboxRetryPayload?
    func retryPayload(messageID: String, room: ChatRoom) async -> ChatOutgoingOutboxRetryPayload?
    func completeServerConfirmedMessage(_ message: ChatMessage) async
    func deleteLocalFailedMessage(_ message: ChatMessage) async
    func cancelPendingMessages(roomID: String) async
}

protocol ChatServerConfirmedMessageReconciling {
    func reconcileServerConfirmedMessages(_ messages: [ChatMessage]) async throws
}

final class ChatOutgoingOutboxUseCase: ChatOutgoingOutboxUseCaseProtocol, ChatServerConfirmedMessageReconciling {
    private static let failedMediaRetentionInterval: TimeInterval = 7 * 24 * 60 * 60
    private let outboxPersistence: ChatOutgoingOutboxPersisting
    private let messagePersistence: ChatFailedOutgoingMessagePersisting
    private let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    private let videoStorageRepository: FirebaseVideoStorageRepositoryProtocol
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private let outboxRootProvider: () -> URL?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        outboxPersistence: ChatOutgoingOutboxPersisting,
        messagePersistence: ChatFailedOutgoingMessagePersisting,
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        videoStorageRepository: FirebaseVideoStorageRepositoryProtocol,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = { Date() },
        outboxRootProvider: @escaping () -> URL? = {
            try? FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("ChatOutgoingOutbox", isDirectory: true)
        }
    ) {
        self.outboxPersistence = outboxPersistence
        self.messagePersistence = messagePersistence
        self.imageStorageRepository = imageStorageRepository
        self.videoStorageRepository = videoStorageRepository
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.outboxRootProvider = outboxRootProvider
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func stageTextMessage(_ message: ChatMessage) async {
        var failedMessage = message
        failedMessage.isFailed = true
        await persistFailedMessage(failedMessage)
        await saveRecord(
            messageID: message.ID,
            roomID: message.roomID,
            kind: .text,
            stage: .failed,
            localPayloadJSON: nil,
            uploadedPayloadJSON: nil,
            error: nil
        )
    }

    func stageImageMessage(_ message: ChatMessage, pairs: [ProcessedImage]) async {
        guard let payload = try? preserveImagePayload(roomID: message.roomID, messageID: message.ID, pairs: pairs) else {
            var failedMessage = message
            failedMessage.isFailed = true
            await persistFailedMessage(failedMessage)
            await saveRecord(
                messageID: message.ID,
                roomID: message.roomID,
                kind: .images,
                stage: .failed,
                localPayloadJSON: nil,
                uploadedPayloadJSON: nil,
                error: "failed_to_preserve_image_payload"
            )
            return
        }

        var failedMessage = message
        failedMessage.isFailed = true
        failedMessage.attachments = makeImageAttachments(from: payload)
        await persistFailedMessage(failedMessage)

        await saveRecord(
            messageID: message.ID,
            roomID: message.roomID,
            kind: .images,
            stage: .needsUpload,
            localPayloadJSON: encodeToString(payload),
            uploadedPayloadJSON: nil,
            error: nil
        )
    }

    func stageVideoMessage(_ message: ChatMessage, prepared: PreparedVideo) async {
        guard let payload = try? preserveVideoPayload(roomID: message.roomID, messageID: message.ID, prepared: prepared) else {
            var failedMessage = message
            failedMessage.isFailed = true
            await persistFailedMessage(failedMessage)
            await saveRecord(
                messageID: message.ID,
                roomID: message.roomID,
                kind: .video,
                stage: .failed,
                localPayloadJSON: nil,
                uploadedPayloadJSON: nil,
                error: "failed_to_preserve_video_payload"
            )
            return
        }

        var failedMessage = message
        failedMessage.isFailed = true
        failedMessage.attachments = [makeVideoAttachment(from: payload)]
        await persistFailedMessage(failedMessage)

        await saveRecord(
            messageID: message.ID,
            roomID: message.roomID,
            kind: .video,
            stage: .needsUpload,
            localPayloadJSON: encodeToString(payload),
            uploadedPayloadJSON: nil,
            error: nil
        )
    }

    func markImageUploadCompleted(messageID: String, attachments: [Attachment]) async {
        guard var record = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: messageID) else { return }
        record.stage = .uploaded
        record.updatedAt = dateProvider()
        record.uploadedPayloadJSON = encodeToString(ChatOutgoingOutboxUploadedImagesPayload(attachments: attachments))
        record.lastError = nil
        try? await outboxPersistence.saveOutgoingOutboxRecord(record)

        if let failed = try? await messagePersistence.fetchMessage(id: messageID, inRoom: record.roomID) {
            var updated = failed
            updated.isFailed = true
            updated.attachments = attachments
            await persistFailedMessage(updated)
        }
    }

    func markVideoUploadCompleted(messageID: String, payload: VideoMetaPayload) async {
        guard var record = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: messageID) else { return }
        record.stage = .uploaded
        record.updatedAt = dateProvider()
        record.uploadedPayloadJSON = encodeToString(payload)
        record.lastError = nil
        try? await outboxPersistence.saveOutgoingOutboxRecord(record)

        if let failed = try? await messagePersistence.fetchMessage(id: messageID, inRoom: record.roomID) {
            var updated = failed
            updated.isFailed = true
            updated.attachments = [makeVideoAttachment(from: payload)]
            await persistFailedMessage(updated)
        }
    }

    func markMediaReservation(messageID: String, reservation: ChatMediaUploadReservation) async {
        guard var updated = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: messageID) else { return }
        let record = updated
        let localPaths: [String]
        switch record.kind {
        case .images:
            let payload: ChatOutgoingOutboxImagePayload? = decodeFromString(record.localPayloadJSON)
            localPaths = payload?.items.sorted(by: { $0.index < $1.index }).map(\.originalFilePath) ?? []
        case .video:
            let payload: ChatOutgoingOutboxVideoPayload? = decodeFromString(record.localPayloadJSON)
            localPaths = payload.map { [$0.compressedFilePath] } ?? []
        case .text:
            return
        }
        guard !localPaths.isEmpty,
              reservation.targets.allSatisfy({ localPaths.indices.contains($0.sourceIndex) }) else { return }
        let session = ChatMediaUploadSessionPayload(
            uploadID: reservation.uploadID,
            clientMutationID: reservation.clientMutationID,
            kind: record.kind == .video ? "video" : "images",
            expiresAt: reservation.expiresAt
        )
        updated.stage = .uploading
        updated.updatedAt = dateProvider()
        updated.uploadID = reservation.uploadID
        updated.clientMutationID = reservation.clientMutationID
        updated.processingStatus = reservation.processingStatus.rawValue
        updated.statusCheckedAt = dateProvider()
        updated.expiresAt = reservation.expiresAt
        updated.sessionPayloadJSON = encodeToString(session)
        updated.terminalAt = nil
        updated.lastError = nil
        try? await outboxPersistence.saveOutgoingOutboxRecord(updated)
    }

    func markMediaProcessing(messageID: String, snapshot: ChatMediaProcessingSnapshot) async {
        guard var record = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: messageID) else { return }
        record.processingStatus = snapshot.processingStatus.rawValue
        record.statusCheckedAt = dateProvider()
        record.updatedAt = dateProvider()
        record.lastError = snapshot.failureCode
        switch snapshot.processingStatus {
        case .uploading: record.stage = .uploading
        case .queued: record.stage = .queued
        case .processing: record.stage = .processing
        case .ready:
            record.stage = .sending
            record.terminalAt = dateProvider()
        case .canceled:
            record.stage = .canceled
            record.terminalAt = dateProvider()
            record.sessionPayloadJSON = nil
        case .failed:
            record.stage = .failed
            record.terminalAt = dateProvider()
            record.sessionPayloadJSON = nil
        case .expired:
            record.stage = .expired
            record.terminalAt = dateProvider()
            record.sessionPayloadJSON = nil
        }
        try? await outboxPersistence.saveOutgoingOutboxRecord(record)
    }

    func markMediaRestoreRequiresManualRetry(messageID: String) async {
        guard var record = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: messageID) else {
            return
        }
        record.stage = .failed
        record.updatedAt = dateProvider()
        record.terminalAt = dateProvider()
        record.processingStatus = ChatMediaServerProcessingStatus.failed.rawValue
        record.statusCheckedAt = dateProvider()
        record.sessionPayloadJSON = nil
        record.lastError = "restore_requires_manual_retry"
        try? await outboxPersistence.saveOutgoingOutboxRecord(record)
    }

    func mediaSessionPayload(messageID: String) async -> ChatMediaUploadSessionPayload? {
        guard let record = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: messageID) else {
            return nil
        }
        return decodeFromString(record.sessionPayloadJSON)
    }

    func pendingMediaRecords(roomID: String) async -> [ChatOutgoingOutboxRecord] {
        let records = (try? await outboxPersistence.fetchOutgoingOutboxRecords(roomID: roomID)) ?? []
        let retentionCutoff = dateProvider().addingTimeInterval(-Self.failedMediaRetentionInterval)
        let expiredFailures = records.filter { record in
            guard record.kind != .text, record.stage == .failed else { return false }
            return (record.terminalAt ?? record.updatedAt) <= retentionCutoff
        }
        for record in expiredFailures {
            try? await messagePersistence.hardDeleteMessage(id: record.messageID, inRoom: record.roomID)
            try? await outboxPersistence.deleteOutgoingOutboxRecord(messageID: record.messageID)
            deleteLocalOutboxFiles(roomID: record.roomID, messageID: record.messageID)
        }
        let expiredIDs = Set(expiredFailures.map(\.messageID))
        return records.filter {
            $0.kind != .text
                && !expiredIDs.contains($0.messageID)
                && ![.canceled, .expired].contains($0.stage)
        }
    }

    func markFailed(message: ChatMessage, error: Error?) async {
        guard var record = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: message.ID) else {
            var failedMessage = message
            failedMessage.isFailed = true
            await stageTextMessage(failedMessage)
            return
        }
        var failedMessage = message
        failedMessage.isFailed = true
        failedMessage.attachments = displayAttachments(for: record, fallback: message.attachments)
        await persistFailedMessage(failedMessage)

        let now = dateProvider()
        record.stage = record.uploadedPayloadJSON == nil ? .failed : .uploaded
        record.updatedAt = now
        record.terminalAt = record.stage == .failed ? now : nil
        record.sessionPayloadJSON = nil
        record.lastError = error?.localizedDescription
        try? await outboxPersistence.saveOutgoingOutboxRecord(record)
    }

    func retryPayload(for message: ChatMessage, room: ChatRoom) async -> ChatOutgoingOutboxRetryPayload? {
        guard let record = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: message.ID) else {
            if message.isFailed, message.attachments.isEmpty {
                return .text(message)
            }
            return nil
        }

        switch record.kind {
        case .text:
            return .text(message)

        case .images:
            if let uploaded: ChatOutgoingOutboxUploadedImagesPayload = decodeFromString(record.uploadedPayloadJSON),
               !uploaded.attachments.isEmpty {
                return .finalizeImages(room: room, messageID: record.messageID, attachments: uploaded.attachments)
            }
            guard let local: ChatOutgoingOutboxImagePayload = decodeFromString(record.localPayloadJSON),
                  let pairs = makeProcessedImages(from: local),
                  !pairs.isEmpty else { return nil }
            return .uploadImages(room: room, messageID: record.messageID, pairs: pairs)

        case .video:
            if let uploaded: VideoMetaPayload = decodeFromString(record.uploadedPayloadJSON) {
                return .finalizeVideo(roomID: record.roomID, messageID: record.messageID, payload: uploaded)
            }
            guard let local: ChatOutgoingOutboxVideoPayload = decodeFromString(record.localPayloadJSON),
                  let prepared = makePreparedVideo(from: local) else { return nil }
            return .uploadVideo(roomID: record.roomID, messageID: record.messageID, prepared: prepared)
        }
    }

    func retryPayload(messageID: String, room: ChatRoom) async -> ChatOutgoingOutboxRetryPayload? {
        guard let message = try? await messagePersistence.fetchMessage(id: messageID, inRoom: room.id) else {
            return nil
        }
        return await retryPayload(for: message, room: room)
    }

    func completeServerConfirmedMessage(_ message: ChatMessage) async {
        guard !message.isFailed else { return }
        try? await messagePersistence.saveChatMessages([message])
        try? await reconcileServerConfirmedMessages([message])
    }

    func reconcileServerConfirmedMessages(_ messages: [ChatMessage]) async throws {
        var seenIDs = Set<String>()
        let confirmed = messages.filter {
            !$0.isFailed && !$0.ID.isEmpty && seenIDs.insert($0.ID).inserted
        }
        guard !confirmed.isEmpty else { return }

        let records = try await outboxPersistence.fetchOutgoingOutboxRecords(
            messageIDs: confirmed.map(\.ID)
        )
        guard !records.isEmpty else { return }

        try await outboxPersistence.deleteOutgoingOutboxRecords(
            messageIDs: records.map(\.messageID)
        )
        for record in records {
            deleteLocalOutboxFiles(roomID: record.roomID, messageID: record.messageID)
        }
    }

    func deleteLocalFailedMessage(_ message: ChatMessage) async {
        let record = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: message.ID)
        try? await messagePersistence.hardDeleteMessage(id: message.ID, inRoom: message.roomID)
        try? await outboxPersistence.deleteOutgoingOutboxRecord(messageID: message.ID)
        deleteLocalOutboxFiles(roomID: message.roomID, messageID: message.ID)
        deleteUploadedStorageFiles(message: message, record: record)
    }

    func cancelPendingMessages(roomID: String) async {
        guard let records = try? await outboxPersistence.fetchOutgoingOutboxRecords(roomID: roomID),
              !records.isEmpty else { return }
        try? await outboxPersistence.deleteOutgoingOutboxRecords(roomID: roomID)
        for record in records {
            try? await messagePersistence.hardDeleteMessage(
                id: record.messageID,
                inRoom: record.roomID
            )
            deleteLocalOutboxFiles(roomID: record.roomID, messageID: record.messageID)
        }
    }

    private func saveRecord(
        messageID: String,
        roomID: String,
        kind: ChatOutgoingOutboxKind,
        stage: ChatOutgoingOutboxStage,
        localPayloadJSON: String?,
        uploadedPayloadJSON: String?,
        error: String?
    ) async {
        let now = dateProvider()
        let existing = try? await outboxPersistence.fetchOutgoingOutboxRecord(messageID: messageID)
        let record = ChatOutgoingOutboxRecord(
            messageID: messageID,
            roomID: roomID,
            kind: kind,
            stage: stage,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            localPayloadJSON: localPayloadJSON ?? existing?.localPayloadJSON,
            uploadedPayloadJSON: uploadedPayloadJSON ?? existing?.uploadedPayloadJSON,
            lastError: error,
            uploadID: existing?.uploadID,
            clientMutationID: existing?.clientMutationID,
            processingStatus: existing?.processingStatus,
            statusCheckedAt: existing?.statusCheckedAt,
            terminalAt: existing?.terminalAt,
            expiresAt: existing?.expiresAt,
            sessionPayloadJSON: existing?.sessionPayloadJSON
        )
        try? await outboxPersistence.saveOutgoingOutboxRecord(record)
    }

    private func persistFailedMessage(_ message: ChatMessage) async {
        try? await messagePersistence.saveChatMessages([message])
    }

    private func preserveImagePayload(
        roomID: String,
        messageID: String,
        pairs: [ProcessedImage]
    ) throws -> ChatOutgoingOutboxImagePayload {
        let imageDir = try ensureMessageDirectory(roomID: roomID, messageID: messageID)
            .appendingPathComponent("images", isDirectory: true)
        try fileManager.createDirectory(at: imageDir, withIntermediateDirectories: true)

        let items = try pairs.sorted(by: { $0.index < $1.index }).map { pair in
            let sourceExtension: String
            switch pair.mediaFormat {
            case "png": sourceExtension = "png"
            case "gif": sourceExtension = "gif"
            default: sourceExtension = "jpg"
            }
            let originalURL = imageDir.appendingPathComponent("\(pair.index)_original.\(sourceExtension)")
            let thumbURL = imageDir.appendingPathComponent("\(pair.index)_thumb.jpg")

            if fileManager.fileExists(atPath: originalURL.path) {
                try? fileManager.removeItem(at: originalURL)
            }
            try fileManager.copyItem(at: pair.originalFileURL, to: originalURL)
            try pair.thumbData.write(to: thumbURL, options: .atomic)
            try ChatOutboxFilePolicy.apply(to: originalURL, fileManager: fileManager)
            try ChatOutboxFilePolicy.apply(to: thumbURL, fileManager: fileManager)

            return ChatOutgoingOutboxImagePayload.Item(
                index: pair.index,
                originalFilePath: relativeOutboxPath(for: originalURL),
                thumbFilePath: relativeOutboxPath(for: thumbURL),
                originalWidth: pair.originalWidth,
                originalHeight: pair.originalHeight,
                bytesOriginal: pair.bytesOriginal,
                sha256: pair.sha256,
                contentType: pair.contentType,
                mediaFormat: pair.mediaFormat,
                isAnimated: pair.isAnimated
            )
        }

        return ChatOutgoingOutboxImagePayload(items: items)
    }

    private func preserveVideoPayload(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo
    ) throws -> ChatOutgoingOutboxVideoPayload {
        let videoDir = try ensureMessageDirectory(roomID: roomID, messageID: messageID)
            .appendingPathComponent("video", isDirectory: true)
        try fileManager.createDirectory(at: videoDir, withIntermediateDirectories: true)

        let videoURL = videoDir.appendingPathComponent("video.mp4")
        let thumbURL = videoDir.appendingPathComponent("thumb.jpg")
        if fileManager.fileExists(atPath: videoURL.path) {
            try? fileManager.removeItem(at: videoURL)
        }
        try fileManager.copyItem(at: prepared.compressedFileURL, to: videoURL)
        try prepared.thumbnailData.write(to: thumbURL, options: .atomic)
        try ChatOutboxFilePolicy.apply(to: videoURL, fileManager: fileManager)
        try ChatOutboxFilePolicy.apply(to: thumbURL, fileManager: fileManager)

        return ChatOutgoingOutboxVideoPayload(
            compressedFilePath: relativeOutboxPath(for: videoURL),
            thumbnailFilePath: relativeOutboxPath(for: thumbURL),
            sha256: prepared.sha256,
            duration: prepared.duration,
            width: prepared.width,
            height: prepared.height,
            sizeBytes: prepared.sizeBytes,
            approxBitrateMbps: prepared.approxBitrateMbps,
            preset: prepared.preset.chatPayloadCode
        )
    }

    private func ensureMessageDirectory(roomID: String, messageID: String) throws -> URL {
        guard let root = outboxRootProvider() else {
            throw NSError(domain: "ChatOutgoingOutbox", code: -1, userInfo: [NSLocalizedDescriptionKey: "outbox root unavailable"])
        }
        let directory = root
            .appendingPathComponent(roomID, isDirectory: true)
            .appendingPathComponent(messageID, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try ChatOutboxFilePolicy.apply(to: directory, fileManager: fileManager)
        return directory
    }

    private func makeProcessedImages(from payload: ChatOutgoingOutboxImagePayload) -> [ProcessedImage]? {
        var pairs: [ProcessedImage] = []
        for item in payload.items.sorted(by: { $0.index < $1.index }) {
            guard let originalURL = localOutboxURL(from: item.originalFilePath),
                  let thumbURL = localOutboxURL(from: item.thumbFilePath) else {
                return nil
            }
            guard fileManager.fileExists(atPath: originalURL.path),
                  let thumbData = try? Data(contentsOf: thumbURL) else { return nil }
            pairs.append(ProcessedImage(
                index: item.index,
                originalFileURL: originalURL,
                thumbData: thumbData,
                originalWidth: item.originalWidth,
                originalHeight: item.originalHeight,
                bytesOriginal: item.bytesOriginal,
                sha256: item.sha256,
                contentType: item.contentType,
                mediaFormat: item.mediaFormat,
                isAnimated: item.isAnimated
            ))
        }
        return pairs
    }

    private func makePreparedVideo(from payload: ChatOutgoingOutboxVideoPayload) -> PreparedVideo? {
        guard let videoURL = localOutboxURL(from: payload.compressedFilePath),
              let thumbURL = localOutboxURL(from: payload.thumbnailFilePath) else {
            return nil
        }
        guard fileManager.fileExists(atPath: videoURL.path),
              let thumbData = try? Data(contentsOf: thumbURL) else { return nil }

        return PreparedVideo(
            compressedFileURL: videoURL,
            thumbnailData: thumbData,
            sha256: payload.sha256,
            duration: payload.duration,
            width: payload.width,
            height: payload.height,
            sizeBytes: payload.sizeBytes,
            approxBitrateMbps: payload.approxBitrateMbps,
            preset: VideoUploadPreset(chatPayloadCode: payload.preset)
        )
    }

    private func displayAttachments(
        for record: ChatOutgoingOutboxRecord,
        fallback: [Attachment]
    ) -> [Attachment] {
        switch record.kind {
        case .text:
            return fallback
        case .images:
            if let uploaded: ChatOutgoingOutboxUploadedImagesPayload = decodeFromString(record.uploadedPayloadJSON),
               !uploaded.attachments.isEmpty {
                return uploaded.attachments
            }
            if let local: ChatOutgoingOutboxImagePayload = decodeFromString(record.localPayloadJSON) {
                return makeImageAttachments(from: local)
            }
            return fallback
        case .video:
            if let uploaded: VideoMetaPayload = decodeFromString(record.uploadedPayloadJSON) {
                return [makeVideoAttachment(from: uploaded)]
            }
            if let local: ChatOutgoingOutboxVideoPayload = decodeFromString(record.localPayloadJSON) {
                return [makeVideoAttachment(from: local)]
            }
            return fallback
        }
    }

    private func makeImageAttachments(from payload: ChatOutgoingOutboxImagePayload) -> [Attachment] {
        payload.items.sorted(by: { $0.index < $1.index }).map { item in
            let sourcePath = displayPath(from: item.originalFilePath)
            return Attachment(
                type: .image,
                index: item.index,
                pathThumb: sourcePath,
                pathOriginal: sourcePath,
                width: item.originalWidth,
                height: item.originalHeight,
                bytesOriginal: item.bytesOriginal,
                hash: item.sha256,
                blurhash: nil,
                duration: nil,
                mediaFormat: item.mediaFormat,
                isAnimated: item.isAnimated
            )
        }
    }

    private func makeVideoAttachment(from payload: ChatOutgoingOutboxVideoPayload) -> Attachment {
        Attachment(
            type: .video,
            index: 0,
            pathThumb: displayPath(from: payload.thumbnailFilePath),
            pathOriginal: displayPath(from: payload.compressedFilePath),
            width: payload.width,
            height: payload.height,
            bytesOriginal: Int(payload.sizeBytes),
            hash: payload.sha256,
            blurhash: nil,
            duration: payload.duration,
            approxBitrateMbps: payload.approxBitrateMbps,
            preset: payload.preset
        )
    }

    private func relativeOutboxPath(for fileURL: URL) -> String {
        guard let root = outboxRootProvider() else { return fileURL.path }
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return filePath }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func localOutboxURL(from storedPath: String) -> URL? {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let root = outboxRootProvider() else { return nil }

        if trimmed.hasPrefix("file://"),
           let url = URL(string: trimmed),
           url.isFileURL {
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
            return migratedOutboxURL(fromAbsolutePath: url.path, root: root)
        }

        if trimmed.hasPrefix("/") {
            if fileManager.fileExists(atPath: trimmed) {
                return URL(fileURLWithPath: trimmed)
            }
            return migratedOutboxURL(fromAbsolutePath: trimmed, root: root)
        }

        return root.appendingPathComponent(trimmed)
    }

    private func displayPath(from storedPath: String) -> String {
        localOutboxURL(from: storedPath)?.path ?? storedPath
    }

    private func migratedOutboxURL(fromAbsolutePath path: String, root: URL) -> URL? {
        guard let range = path.range(of: "ChatOutgoingOutbox/") else { return nil }
        let relative = String(path[range.upperBound...])
        let url = root.appendingPathComponent(relative)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func makeVideoAttachment(from payload: VideoMetaPayload) -> Attachment {
        payload.confirmedAttachment
    }

    private func deleteLocalOutboxFiles(roomID: String, messageID: String) {
        guard let root = outboxRootProvider() else { return }
        let directory = root
            .appendingPathComponent(roomID, isDirectory: true)
            .appendingPathComponent(messageID, isDirectory: true)
        try? fileManager.removeItem(at: directory)
    }

    private func deleteUploadedStorageFiles(message: ChatMessage, record: ChatOutgoingOutboxRecord?) {
        var paths = message.attachments.flatMap { [$0.pathThumb, $0.pathOriginal] }
        if let uploadedImages: ChatOutgoingOutboxUploadedImagesPayload = decodeFromString(record?.uploadedPayloadJSON) {
            paths.append(contentsOf: uploadedImages.attachments.flatMap { [$0.pathThumb, $0.pathOriginal] })
        }
        if let uploadedVideo: VideoMetaPayload = decodeFromString(record?.uploadedPayloadJSON) {
            paths.append(uploadedVideo.thumbnailPath)
            paths.append(uploadedVideo.storagePath)
        }

        let uniquePaths = Array(Set(paths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty && !$0.hasPrefix("file://") && !$0.hasPrefix("/") }
        for path in uniquePaths {
            if path.lowercased().hasSuffix(".mp4") {
                videoStorageRepository.deleteVideoFromStorage(path: path)
            } else {
                imageStorageRepository.deleteImageFromStorage(path: path)
            }
        }
    }

    private func encodeToString<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func decodeFromString<T: Decodable>(_ string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}

extension VideoUploadPreset {
    init(chatPayloadCode: String) {
        switch chatPayloadCode {
        case "dataSaver720":
            self = .dataSaver720
        case "high1080":
            self = .high1080
        default:
            self = .standard720
        }
    }
}
