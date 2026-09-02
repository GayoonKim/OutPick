//
//  ChatMessageType.swift
//  OutPick
//
//  Created by Codex on 6/16/26.
//

import Foundation

enum ChatMessageType: String, Codable, Hashable, Sendable {
    case text
    case image
    case video
    case lookbookShare
    case roomRoleEvent

    init?(legacyRawValue rawValue: String?) {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "text":
            self = .text
        case "image":
            self = .image
        case "video":
            self = .video
        case "lookbookshare", "lookbook_share":
            self = .lookbookShare
        case "roomroleevent", "room_role_event":
            self = .roomRoleEvent
        default:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let messageType = ChatMessageType(legacyRawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported chat message type: \(rawValue)"
            )
        }
        self = messageType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum RoomRoleEventKind: String, Codable, Hashable, Sendable {
    case moderatorAssigned
    case moderatorRevoked
    case moderatorResigned
    case ownershipTransferred
}

struct RoomRoleEventPayload: Codable, Hashable, Sendable {
    let kind: RoomRoleEventKind
    let subjectUID: String?
    let subjectNicknameSnapshot: String

    init(
        kind: RoomRoleEventKind,
        subjectUID: String?,
        subjectNicknameSnapshot: String
    ) {
        self.kind = kind
        self.subjectUID = subjectUID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.subjectNicknameSnapshot = subjectNicknameSnapshot
    }

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "kind": kind.rawValue,
            "subjectNicknameSnapshot": subjectNicknameSnapshot
        ]
        if let subjectUID {
            result["subjectUID"] = subjectUID
        }
        return result
    }

    var displayText: String {
        let nickname = subjectNicknameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNickname = nickname.isEmpty ? "알 수 없는 사용자" : nickname
        switch kind {
        case .moderatorAssigned:
            return "\(resolvedNickname)님이 관리자로 지정되었어요"
        case .moderatorRevoked:
            return "\(resolvedNickname)님의 관리자 권한이 해제되었어요"
        case .moderatorResigned:
            return "\(resolvedNickname)님이 관리자에서 물러났어요"
        case .ownershipTransferred:
            return "\(resolvedNickname)님이 방장이 되었어요"
        }
    }

    static func from(_ raw: Any?) -> RoomRoleEventPayload? {
        guard let data = raw as? [String: Any],
              let rawKind = data["kind"] as? String,
              let kind = RoomRoleEventKind(rawValue: rawKind),
              let nickname = data["subjectNicknameSnapshot"] as? String,
              !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return RoomRoleEventPayload(
            kind: kind,
            subjectUID: data["subjectUID"] as? String,
            subjectNicknameSnapshot: nickname
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
