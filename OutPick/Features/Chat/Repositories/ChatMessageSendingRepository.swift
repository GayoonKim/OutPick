//
//  ChatMessageSendingRepository.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

enum ChatMessageEmitAckMapper {
    static func receipt(
        from ackItems: [Any],
        roomID: String,
        fallbackMessageID: String
    ) -> ChatMessageSendReceipt? {
        guard isSuccess(ackItems) else { return nil }
        guard let dict = ackItems.first as? [String: Any] else {
            return ChatMessageSendReceipt(
                roomID: roomID,
                messageID: fallbackMessageID,
                seq: nil
            )
        }

        return ChatMessageSendReceipt(
            roomID: roomID,
            messageID: stringValue(dict["messageID"]) ?? fallbackMessageID,
            seq: int64Value(dict["seq"]),
            duplicate: boolValue(dict["duplicate"]) ?? false
        )
    }

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

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? UInt64 {
            return value > UInt64(Int64.max) ? Int64.max : Int64(value)
        }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}

protocol ChatMessageSendingRepositoryProtocol {
    func sendMessage(_ message: ChatMessage, to room: ChatRoom) async throws -> ChatMessageSendReceipt
}

protocol ChatTextMessageSocketSending {
    func sendMessage(
        _ room: ChatRoom,
        _ message: ChatMessage,
        ackTimeout: Double
    ) async throws -> ChatMessageSendReceipt
}

final class SocketChatMessageSendingRepository: ChatMessageSendingRepositoryProtocol {
    private let socketManager: ChatTextMessageSocketSending

    init(socketManager: ChatTextMessageSocketSending = RealtimeSocketService.shared) {
        self.socketManager = socketManager
    }

    func sendMessage(_ message: ChatMessage, to room: ChatRoom) async throws -> ChatMessageSendReceipt {
        try await socketManager.sendMessage(room, message, ackTimeout: 5.0)
    }
}

extension RealtimeSocketService: ChatTextMessageSocketSending {}
