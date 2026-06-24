//
//  ChatMessageSendingRepository.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

enum ChatMessageEmitAckMapper {
    static func isSuccess(_ ackItems: [Any]) -> Bool {
        guard let first = ackItems.first else {
            // 일부 서버는 성공 ACK payload를 비워두므로 빈 ACK는 성공으로 유지한다.
            return true
        }

        if let dict = first as? [String: Any] {
            if let ok = dict["ok"] as? Bool { return ok || ((dict["duplicate"] as? Bool) ?? false) }
            if let success = dict["success"] as? Bool { return success || ((dict["duplicate"] as? Bool) ?? false) }
            if let duplicate = dict["duplicate"] as? Bool, duplicate { return true }

            if let status = (dict["status"] as? String)?.lowercased() {
                if ["ok", "success", "accepted", "duplicate"].contains(status) { return true }
                if ["error", "failed", "fail", "timeout", "no ack", "no_ack"].contains(status) { return false }
            }
            if dict["error"] != nil { return false }
            return true
        }

        if let text = first as? String {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.isEmpty { return true }
            if ["no ack", "no_ack", "timeout"].contains(normalized) { return false }
            if normalized.contains("error") || normalized.contains("fail") { return false }
            return true
        }

        return true
    }
}

protocol ChatMessageSendingRepositoryProtocol {
    func sendMessage(_ message: ChatMessage, to room: ChatRoom) async throws
}

protocol ChatTextMessageSocketSending {
    func sendMessage(_ room: ChatRoom, _ message: ChatMessage, ackTimeout: Double) async throws
}

final class SocketChatMessageSendingRepository: ChatMessageSendingRepositoryProtocol {
    private let socketManager: ChatTextMessageSocketSending

    init(socketManager: ChatTextMessageSocketSending = RealtimeSocketService.shared) {
        self.socketManager = socketManager
    }

    func sendMessage(_ message: ChatMessage, to room: ChatRoom) async throws {
        try await socketManager.sendMessage(room, message, ackTimeout: 5.0)
    }
}

extension RealtimeSocketService: ChatTextMessageSocketSending {}
