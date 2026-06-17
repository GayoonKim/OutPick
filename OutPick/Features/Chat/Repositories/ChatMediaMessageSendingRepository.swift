//
//  ChatMediaMessageSendingRepository.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

protocol ChatMediaMessageSendingRepositoryProtocol {
    func sendImages(
        _ room: ChatRoom,
        attachments: [Attachment],
        senderAvatarPath: String?,
        clientMessageID: String?
    )

    func sendVideo(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?
    )

    func sendFailedVideo(
        roomID: String,
        senderID: String,
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
    func sendImages(
        _ room: ChatRoom,
        _ attachments: [[String: Any]],
        senderAvatarPath: String?,
        clientMessageID: String?
    )

    func sendVideo(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?,
        ackTimeout: Double,
        completion: ((Result<Void, Error>) -> Void)?
    )

    func sendFailedVideos(
        roomID: String,
        senderID: String,
        senderNickname: String,
        localURL: URL,
        thumbData: Data?,
        duration: Double,
        width: Int,
        height: Int,
        presetCode: String
    )
}

final class SocketChatMediaMessageSendingRepository: ChatMediaMessageSendingRepositoryProtocol {
    private let socketManager: ChatMediaSocketSending

    init(socketManager: ChatMediaSocketSending = SocketIOManager.shared) {
        self.socketManager = socketManager
    }

    func sendImages(
        _ room: ChatRoom,
        attachments: [Attachment],
        senderAvatarPath: String?,
        clientMessageID: String?
    ) {
        socketManager.sendImages(
            room,
            attachments.map { $0.toDict() },
            senderAvatarPath: senderAvatarPath,
            clientMessageID: clientMessageID
        )
    }

    func sendVideo(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String?
    ) {
        socketManager.sendVideo(
            roomID: roomID,
            payload: payload,
            senderAvatarPath: senderAvatarPath,
            ackTimeout: 5.0,
            completion: nil
        )
    }

    func sendFailedVideo(
        roomID: String,
        senderID: String,
        senderNickname: String,
        localURL: URL,
        thumbData: Data?,
        duration: Double,
        width: Int,
        height: Int,
        presetCode: String
    ) {
        socketManager.sendFailedVideos(
            roomID: roomID,
            senderID: senderID,
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

extension SocketIOManager: ChatMediaSocketSending {}
