//
//  ChatRoomMediaIndexEntry.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

struct ChatRoomMediaIndexCursor: Hashable {
    let sentAt: Date
    let messageID: String
    let idx: Int
}

struct ChatRoomMediaIndexEntry: Hashable {
    let roomID: String
    let messageID: String
    let idx: Int
    let seq: Int64
    let senderID: String
    let type: Attachment.AttachmentType
    let thumbKey: String?
    let originalKey: String?
    let thumbURL: String?
    let originalURL: String?
    let width: Int?
    let height: Int?
    let bytesOriginal: Int?
    let duration: Double?
    let hash: String?
    let isDeleted: Bool
    let sentAt: Date

    var documentID: String {
        "\(messageID)_\(idx)"
    }

    var cursor: ChatRoomMediaIndexCursor {
        ChatRoomMediaIndexCursor(sentAt: sentAt, messageID: messageID, idx: idx)
    }

    static func entries(from message: ChatMessage) -> [ChatRoomMediaIndexEntry] {
        let sentAt = message.sentAt ?? Date()

        return message.attachments
            .filter { $0.type == .image || $0.type == .video }
            .sorted { $0.index < $1.index }
            .map { attachment in
                let hash = attachment.hash.isEmpty ? nil : attachment.hash
                return ChatRoomMediaIndexEntry(
                    roomID: message.roomID,
                    messageID: message.ID,
                    idx: attachment.index,
                    seq: message.seq,
                    senderID: message.senderID,
                    type: attachment.type,
                    thumbKey: hash,
                    originalKey: hash.map { "\($0):orig" },
                    thumbURL: attachment.pathThumb.isEmpty ? nil : attachment.pathThumb,
                    originalURL: attachment.pathOriginal.isEmpty ? nil : attachment.pathOriginal,
                    width: attachment.width > 0 ? attachment.width : nil,
                    height: attachment.height > 0 ? attachment.height : nil,
                    bytesOriginal: attachment.bytesOriginal > 0 ? attachment.bytesOriginal : nil,
                    duration: attachment.duration,
                    hash: hash,
                    isDeleted: message.isDeleted,
                    sentAt: sentAt
                )
            }
    }
}
