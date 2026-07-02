//
//  ChatMediaMessageSendingRepository.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

protocol ChatMediaMessageSendingRepositoryProtocol {
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
    ) async throws

    func sendVideo(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?
    ) async throws

    func sendFailedVideo(
        roomID: String,
        senderUID: String,
        senderEmail: String?,
        senderNickname: String,
        localURL: URL,
        thumbData: Data?,
        duration: Double,
        width: Int,
        height: Int,
        presetCode: String
    )
}

protocol ChatMediaSocketSending {
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
    ) async throws

    func sendVideoAwaitingAck(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?,
        ackTimeout: Double
    ) async throws

    func sendFailedVideos(
        roomID: String,
        senderUID: String,
        senderEmail: String?,
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
    ) async throws {
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
    ) async throws {
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
        senderEmail: String?,
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
                senderEmail: senderEmail,
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
