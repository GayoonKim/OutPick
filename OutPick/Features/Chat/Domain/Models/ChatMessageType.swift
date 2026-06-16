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
