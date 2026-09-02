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
    let senderUID: String
    let type: Attachment.AttachmentType
    let bucketThumb: String?
    let bucketOriginal: String?
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

    init(
        roomID: String,
        messageID: String,
        idx: Int,
        seq: Int64,
        senderUID: String,
        type: Attachment.AttachmentType,
        bucketThumb: String? = nil,
        bucketOriginal: String? = nil,
        thumbKey: String?,
        originalKey: String?,
        thumbURL: String?,
        originalURL: String?,
        width: Int?,
        height: Int?,
        bytesOriginal: Int?,
        duration: Double?,
        hash: String?,
        isDeleted: Bool,
        sentAt: Date
    ) {
        self.roomID = roomID
        self.messageID = messageID
        self.idx = idx
        self.seq = seq
        self.senderUID = senderUID
        self.type = type
        self.bucketThumb = bucketThumb
        self.bucketOriginal = bucketOriginal
        self.thumbKey = thumbKey
        self.originalKey = originalKey
        self.thumbURL = thumbURL
        self.originalURL = originalURL
        self.width = width
        self.height = height
        self.bytesOriginal = bytesOriginal
        self.duration = duration
        self.hash = hash
        self.isDeleted = isDeleted
        self.sentAt = sentAt
    }

    var documentID: String {
        "\(messageID)_\(idx)"
    }

    var cursor: ChatRoomMediaIndexCursor {
        ChatRoomMediaIndexCursor(sentAt: sentAt, messageID: messageID, idx: idx)
    }

    var thumbResourcePath: String? {
        Self.resourcePath(bucket: bucketThumb, path: thumbURL)
    }

    var originalResourcePath: String? {
        Self.resourcePath(bucket: bucketOriginal, path: originalURL)
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
                    senderUID: message.senderUID,
                    type: attachment.type,
                    bucketThumb: attachment.bucketThumb,
                    bucketOriginal: attachment.bucketOriginal,
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

    private static func resourcePath(bucket: String?, path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        guard let bucket = bucket?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bucket.isEmpty,
              !path.hasPrefix("/") && !path.hasPrefix("file://") && !path.hasPrefix("gs://") else {
            return path
        }
        return "gs://\(bucket)/\(path)"
    }
}
