//
//  LookbookChatShareSendingRepository.swift
//  OutPick
//
//  Created by Codex on 6/16/26.
//

import Foundation

struct LookbookChatShareSendResult: Equatable, Sendable {
    let roomID: String
    let messageID: String
    let seq: Int64?
}

enum LookbookChatShareError: Error, Equatable, LocalizedError, Sendable {
    case invalidRoomID
    case invalidSharedContent
    case socketDisconnected
    case timeout
    case roomNotFound
    case notJoined
    case roomClosed
    case rateLimited
    case server(String)
    case unknownAck(String)

    var errorDescription: String? {
        switch self {
        case .invalidRoomID:
            return "공유할 채팅방 정보를 확인할 수 없습니다."
        case .invalidSharedContent:
            return "공유할 룩북 정보가 올바르지 않습니다."
        case .socketDisconnected:
            return "채팅 서버에 연결되어 있지 않습니다."
        case .timeout:
            return "채팅 서버 응답이 지연되고 있습니다."
        case .roomNotFound:
            return "채팅방을 찾을 수 없습니다."
        case .notJoined:
            return "참여 중인 채팅방에만 공유할 수 있습니다."
        case .roomClosed:
            return "종료된 채팅방에는 공유할 수 없습니다."
        case .rateLimited:
            return "잠시 후 다시 시도해 주세요."
        case .server(let message):
            return message.isEmpty ? "룩북 공유 전송에 실패했습니다." : message
        case .unknownAck:
            return "채팅 서버 응답을 확인할 수 없습니다."
        }
    }
}

protocol LookbookChatShareSendingRepositoryProtocol {
    func sendLookbookShare(
        sharedContent: LookbookSharedContent,
        to room: ChatRoom
    ) async throws -> LookbookChatShareSendResult
}

protocol LookbookChatShareSocketSending {
    func sendLookbookShare(
        roomID: String,
        sharedContent: LookbookSharedContent,
        ackTimeout: Double
    ) async throws -> LookbookChatShareSendResult
}

final class SocketLookbookChatShareSendingRepository: LookbookChatShareSendingRepositoryProtocol {
    private let socketManager: LookbookChatShareSocketSending
    private let ackTimeout: Double

    init(
        socketManager: LookbookChatShareSocketSending = SocketIOManager.shared,
        ackTimeout: Double = 5.0
    ) {
        self.socketManager = socketManager
        self.ackTimeout = ackTimeout
    }

    func sendLookbookShare(
        sharedContent: LookbookSharedContent,
        to room: ChatRoom
    ) async throws -> LookbookChatShareSendResult {
        guard let roomID = LookbookChatShareRoomPolicy.roomID(from: room) else {
            throw LookbookChatShareError.invalidRoomID
        }

        guard sharedContent.isValid else {
            throw LookbookChatShareError.invalidSharedContent
        }

        return try await socketManager.sendLookbookShare(
            roomID: roomID,
            sharedContent: sharedContent,
            ackTimeout: ackTimeout
        )
    }
}

enum LookbookChatShareAckMapper {
    static func parse(
        _ ackItems: [Any],
        roomID: String,
        fallbackMessageID: String
    ) throws -> LookbookChatShareSendResult {
        guard let first = ackItems.first else {
            return LookbookChatShareSendResult(
                roomID: roomID,
                messageID: fallbackMessageID,
                seq: nil
            )
        }

        if let text = first as? String {
            return try parseTextAck(text, roomID: roomID, fallbackMessageID: fallbackMessageID)
        }

        if let dict = first as? [String: Any] {
            return try parseDictAck(dict, roomID: roomID, fallbackMessageID: fallbackMessageID)
        }

        throw LookbookChatShareError.unknownAck(String(describing: ackItems))
    }

    private static func parseTextAck(
        _ text: String,
        roomID: String,
        fallbackMessageID: String
    ) throws -> LookbookChatShareSendResult {
        let normalized = normalizedAckText(text)
        if normalized.isEmpty {
            return LookbookChatShareSendResult(roomID: roomID, messageID: fallbackMessageID, seq: nil)
        }

        if ["no ack", "no_ack", "timeout"].contains(normalized) {
            throw LookbookChatShareError.timeout
        }

        if normalized.contains("error") || normalized.contains("fail") {
            throw LookbookChatShareError.server(text)
        }

        return LookbookChatShareSendResult(roomID: roomID, messageID: fallbackMessageID, seq: nil)
    }

    private static func parseDictAck(
        _ dict: [String: Any],
        roomID: String,
        fallbackMessageID: String
    ) throws -> LookbookChatShareSendResult {
        let messageID = stringValue(dict["messageID"]) ?? fallbackMessageID
        let seq = int64Value(dict["seq"])

        if boolValue(dict["duplicate"]) == true {
            return LookbookChatShareSendResult(roomID: roomID, messageID: messageID, seq: seq)
        }

        if boolValue(dict["ok"]) == true || boolValue(dict["success"]) == true {
            return LookbookChatShareSendResult(roomID: roomID, messageID: messageID, seq: seq)
        }

        if let status = stringValue(dict["status"])?.lowercased() {
            if ["ok", "success", "accepted", "duplicate"].contains(status) {
                return LookbookChatShareSendResult(roomID: roomID, messageID: messageID, seq: seq)
            }
            if ["error", "failed", "fail"].contains(status) {
                throw mapError(from: dict)
            }
        }

        if boolValue(dict["ok"]) == false || boolValue(dict["success"]) == false || dict["error"] != nil {
            throw mapError(from: dict)
        }

        throw LookbookChatShareError.unknownAck(String(describing: dict))
    }

    private static func mapError(from dict: [String: Any]) -> LookbookChatShareError {
        let code = stringValue(dict["error"]) ?? stringValue(dict["message"]) ?? ""
        switch normalizedAckText(code) {
        case "invalid_room_id":
            return .invalidRoomID
        case "room_not_found":
            return .roomNotFound
        case "not_joined":
            return .notJoined
        case "room_closed":
            return .roomClosed
        case "rate_limited":
            return .rateLimited
        case "timeout", "no_ack", "no ack":
            return .timeout
        default:
            return .server(code)
        }
    }

    private static func normalizedAckText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
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
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }
}

extension LookbookSharedContent {
    var lookbookSharePreviewMessage: String {
        switch contentType {
        case .brand:
            return "브랜드를 공유했어요"
        case .season:
            return "시즌을 공유했어요"
        case .post:
            return "포스트를 공유했어요"
        }
    }
}

extension SocketIOManager: LookbookChatShareSocketSending {}
