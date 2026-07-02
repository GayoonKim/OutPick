//
//  ChatMediaUploadUseCase.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

protocol ChatMediaUploadUseCaseProtocol {
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
    ) async throws

    func cacheFailedImageThumbnails(_ pairs: [ProcessedImage]) async
    func cleanupImageOriginalFiles(_ pairs: [ProcessedImage])
    func cleanupReplacedLocalPreviewFiles(previous: ChatMessage, next: ChatMessage)

    func uploadVideo(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo,
        onProgress: @escaping (Double) -> Void
    ) async throws -> VideoMetaPayload

    func sendUploadedVideo(roomID: String, payload: VideoMetaPayload, ensureReservation: Bool) async throws
    func sendFailedVideo(roomID: String, prepared: PreparedVideo)
}

final class ChatMediaUploadUseCase: ChatMediaUploadUseCaseProtocol {
    private let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    private let videoStorageRepository: FirebaseVideoStorageRepositoryProtocol
    private let sendingRepository: ChatMediaMessageSendingRepositoryProtocol
    private let attachmentImageLoader: ChatAttachmentImageLoading
    private let currentUserProvider: () -> ChatMessageSenderSnapshot
    private let dateProvider: () -> Date
    private let previewDirectoryProvider: () -> URL?
    private let fileManager: FileManager

    init(
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        videoStorageRepository: FirebaseVideoStorageRepositoryProtocol,
        sendingRepository: ChatMediaMessageSendingRepositoryProtocol = SocketChatMediaMessageSendingRepository(),
        attachmentImageLoader: ChatAttachmentImageLoading,
        currentUserProvider: @escaping () -> ChatMessageSenderSnapshot = {
            ChatMessageSenderSnapshot(
                senderUID: LoginManager.shared.getUserUID,
                senderEmail: LoginManager.shared.getUserEmail,
                senderNickname: "",
                senderAvatarPath: nil
            )
        },
        dateProvider: @escaping () -> Date = { Date() },
        previewDirectoryProvider: @escaping () -> URL? = {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        },
        fileManager: FileManager = .default
    ) {
        self.imageStorageRepository = imageStorageRepository
        self.videoStorageRepository = videoStorageRepository
        self.sendingRepository = sendingRepository
        self.attachmentImageLoader = attachmentImageLoader
        self.currentUserProvider = currentUserProvider
        self.dateProvider = dateProvider
        self.previewDirectoryProvider = previewDirectoryProvider
        self.fileManager = fileManager
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
            senderEmail: sender.senderEmail,
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
            senderEmail: sender.senderEmail,
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
    ) async throws {
        guard !attachments.isEmpty else { return }

        if ensureReservation {
            try await sendingRepository.preflightMediaUpload(
                roomID: room.ID ?? "",
                messageID: clientMessageID,
                kind: "images",
                attachmentCount: attachments.count,
                expectedPathCount: attachments.count * 2
            )
        }
        
        try await sendingRepository.sendImages(
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

    func sendUploadedVideo(roomID: String, payload: VideoMetaPayload, ensureReservation: Bool = true) async throws {
        if ensureReservation {
            try await sendingRepository.preflightMediaUpload(
                roomID: roomID,
                messageID: payload.messageID,
                kind: "video",
                attachmentCount: 1,
                expectedPathCount: 2
            )
        }
        try await sendingRepository.sendVideo(
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
            senderEmail: sender.senderEmail,
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
        guard let cachesDir = previewDirectoryProvider() else { return [] }
        let baseDir = cachesDir
            .appendingPathComponent("pending-image-preview", isDirectory: true)
            .appendingPathComponent(messageID, isDirectory: true)
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)

        var attachments: [Attachment] = []
        attachments.reserveCapacity(pairs.count)

        for pair in pairs.sorted(by: { $0.index < $1.index }) {
            let fileName = "\(pair.index)_\(pair.sha256).jpg"
            let fileURL = baseDir.appendingPathComponent(fileName)
            do {
                try pair.thumbData.write(to: fileURL, options: .atomic)
                let localPath = fileURL.absoluteString
                attachments.append(Attachment(
                    type: .image,
                    index: pair.index,
                    pathThumb: localPath,
                    pathOriginal: localPath,
                    width: pair.originalWidth,
                    height: pair.originalHeight,
                    bytesOriginal: pair.bytesOriginal,
                    hash: pair.sha256,
                    blurhash: nil,
                    duration: nil
                ))
            } catch {
                print("pending preview write 실패: \(error)")
            }
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
