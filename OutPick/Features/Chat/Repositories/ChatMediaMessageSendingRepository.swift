//
//  ChatMediaMessageSendingRepository.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

protocol ChatMediaMessageSendingRepositoryProtocol {
    func reserveMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String,
        sources: [ChatMediaSourceDescriptor]
    ) async throws -> ChatMediaUploadReservation

    func finalizeMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String
    ) async throws -> ChatMediaProcessingSnapshot

    func refreshMediaUploadTargets(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaUploadReservation

    func mediaProcessingStatus(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot

    func cancelMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot

    func preflightMediaUpload(
        roomID: String,
        messageID: String,
        kind: String,
        attachmentCount: Int,
        expectedPathCount: Int
    ) async throws

    func sendImages(
        _ room: ChatRoom,
        attachments: [Attachment],
        senderAvatarPath: String?,
        clientMessageID: String?
    ) async throws -> ChatMessageSendReceipt

    func sendVideo(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?
    ) async throws -> ChatMessageSendReceipt

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
    )
}

extension ChatMediaMessageSendingRepositoryProtocol {
    func reserveMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String,
        sources: [ChatMediaSourceDescriptor]
    ) async throws -> ChatMediaUploadReservation {
        throw NSError(domain: "ChatMediaUploadV2", code: -1)
    }

    func finalizeMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String
    ) async throws -> ChatMediaProcessingSnapshot {
        throw NSError(domain: "ChatMediaUploadV2", code: -1)
    }

    func refreshMediaUploadTargets(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaUploadReservation {
        throw NSError(domain: "ChatMediaUploadV2", code: -1)
    }

    func mediaProcessingStatus(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot {
        throw NSError(domain: "ChatMediaUploadV2", code: -1)
    }

    func cancelMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot {
        throw NSError(domain: "ChatMediaUploadV2", code: -1)
    }
}

protocol ChatMediaSocketSending {
    func reserveMediaUploadAwaitingAck(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String,
        sources: [ChatMediaSourceDescriptor],
        ackTimeout: Double
    ) async throws -> ChatMediaUploadReservation

    func finalizeMediaUploadAwaitingAck(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String,
        ackTimeout: Double
    ) async throws -> ChatMediaProcessingSnapshot

    func refreshMediaUploadTargetsAwaitingAck(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        ackTimeout: Double
    ) async throws -> ChatMediaUploadReservation

    func mediaProcessingStatusAwaitingAck(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        ackTimeout: Double
    ) async throws -> ChatMediaProcessingSnapshot

    func cancelMediaUploadAwaitingAck(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        ackTimeout: Double
    ) async throws -> ChatMediaProcessingSnapshot

    func preflightMediaUploadAwaitingAck(
        roomID: String,
        messageID: String,
        kind: String,
        attachmentCount: Int,
        expectedPathCount: Int,
        ackTimeout: Double
    ) async throws

    func sendImagesAwaitingAck(
        _ room: ChatRoom,
        _ attachments: [[String: Any]],
        senderAvatarPath: String?,
        clientMessageID: String?,
        ackTimeout: Double
    ) async throws -> ChatMessageSendReceipt

    func sendVideoAwaitingAck(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?,
        ackTimeout: Double
    ) async throws -> ChatMessageSendReceipt

    func sendFailedVideos(
        roomID: String,
        senderUID: String,
        senderNickname: String,
        localURL: URL,
        thumbData: Data?,
        duration: Double,
        width: Int,
        height: Int,
        presetCode: String
    ) async
}

final class SocketChatMediaMessageSendingRepository: ChatMediaMessageSendingRepositoryProtocol {
    private let socketManager: ChatMediaSocketSending

    init(socketManager: ChatMediaSocketSending = RealtimeSocketService.shared) {
        self.socketManager = socketManager
    }

    func reserveMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String,
        sources: [ChatMediaSourceDescriptor]
    ) async throws -> ChatMediaUploadReservation {
        do {
            return try await socketManager.reserveMediaUploadAwaitingAck(
                roomID: roomID,
                uploadID: uploadID,
                clientMutationID: clientMutationID,
                kind: kind,
                sources: sources,
                ackTimeout: 10
            )
        } catch {
            throw Self.mapReservationError(error)
        }
    }

    static func mapReservationError(_ error: Error) -> Error {
        let socketError = error as NSError
        guard socketError.userInfo["serverErrorCode"] as? String == "active_upload_limit" else {
            return error
        }
        return ChatMediaUploadReservationError.activeUploadLimit
    }

    func finalizeMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String,
        kind: String
    ) async throws -> ChatMediaProcessingSnapshot {
        try await socketManager.finalizeMediaUploadAwaitingAck(
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID,
            kind: kind,
            ackTimeout: 15
        )
    }

    func refreshMediaUploadTargets(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaUploadReservation {
        try await socketManager.refreshMediaUploadTargetsAwaitingAck(
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID,
            ackTimeout: 10
        )
    }

    func mediaProcessingStatus(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot {
        try await socketManager.mediaProcessingStatusAwaitingAck(
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID,
            ackTimeout: 5
        )
    }

    func cancelMediaUpload(
        roomID: String,
        uploadID: String,
        clientMutationID: String
    ) async throws -> ChatMediaProcessingSnapshot {
        try await socketManager.cancelMediaUploadAwaitingAck(
            roomID: roomID,
            uploadID: uploadID,
            clientMutationID: clientMutationID,
            ackTimeout: 5
        )
    }

    func preflightMediaUpload(
        roomID: String,
        messageID: String,
        kind: String,
        attachmentCount: Int,
        expectedPathCount: Int
    ) async throws {
        try await socketManager.preflightMediaUploadAwaitingAck(
            roomID: roomID,
            messageID: messageID,
            kind: kind,
            attachmentCount: attachmentCount,
            expectedPathCount: expectedPathCount,
            ackTimeout: 5.0
        )
    }

    func sendImages(
        _ room: ChatRoom,
        attachments: [Attachment],
        senderAvatarPath: String?,
        clientMessageID: String?
    ) async throws -> ChatMessageSendReceipt {
        try await socketManager.sendImagesAwaitingAck(
            room,
            attachments.map { $0.toDict() },
            senderAvatarPath: senderAvatarPath,
            clientMessageID: clientMessageID,
            ackTimeout: 15.0
        )
    }

    func sendVideo(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?
    ) async throws -> ChatMessageSendReceipt {
        try await socketManager.sendVideoAwaitingAck(
            roomID: roomID,
            payload: payload,
            senderAvatarPath: senderAvatarPath,
            ackTimeout: 5.0
        )
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
        Task {
            await socketManager.sendFailedVideos(
                roomID: roomID,
                senderUID: senderUID,
                senderNickname: senderNickname,
                localURL: localURL,
                thumbData: thumbData,
                duration: duration,
                width: width,
                height: height,
                presetCode: presetCode
            )
        }
    }
}

extension RealtimeSocketService: ChatMediaSocketSending {}
