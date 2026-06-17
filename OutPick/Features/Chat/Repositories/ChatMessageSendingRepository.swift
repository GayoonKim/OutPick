//
//  ChatMessageSendingRepository.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

protocol ChatMessageSendingRepositoryProtocol {
    func sendMessage(_ message: ChatMessage, to room: ChatRoom)
}

protocol ChatTextMessageSocketSending {
    func sendMessage(_ room: ChatRoom, _ message: ChatMessage)
}

final class SocketChatMessageSendingRepository: ChatMessageSendingRepositoryProtocol {
    private let socketManager: ChatTextMessageSocketSending

    init(socketManager: ChatTextMessageSocketSending = SocketIOManager.shared) {
        self.socketManager = socketManager
    }

    func sendMessage(_ message: ChatMessage, to room: ChatRoom) {
        socketManager.sendMessage(room, message)
    }
}

extension SocketIOManager: ChatTextMessageSocketSending {}

