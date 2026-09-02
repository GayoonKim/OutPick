//
//  JoinedRoomListItem.swift
//  OutPick
//
//  Created by Codex on 7/3/26.
//

import Foundation
import FirebaseFirestore

enum ChatRoomMemberRole: String, Codable, Equatable, Sendable {
    case owner
    case moderator
    case member
}

struct JoinedRoomProjection: Equatable {
    let roomID: String
    let role: ChatRoomMemberRole?
    let joinedAt: Date?
    let moderatorSince: Date?
    let lastReadSeq: Int64
    let lastReadUnreadMessageSeq: Int64
    let isClosed: Bool
    let updatedAt: Date?

    init?(
        documentID: String,
        data: [String: Any]
    ) {
        let explicitRoomID = (data["roomID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackRoomID = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRoomID = explicitRoomID?.isEmpty == false ? explicitRoomID! : fallbackRoomID
        guard !resolvedRoomID.isEmpty else { return nil }

        self.roomID = resolvedRoomID
        let rawRole = (data["role"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.role = rawRole.flatMap(ChatRoomMemberRole.init(rawValue:))
        self.joinedAt = Self.dateValue(data["joinedAt"])
        self.moderatorSince = Self.dateValue(data["moderatorSince"])
        self.lastReadSeq = max(Int64(0), Self.int64Value(data["lastReadSeq"]) ?? 0)
        self.lastReadUnreadMessageSeq = max(
            Int64(0),
            Self.int64Value(data["lastReadUnreadMessageSeq"]) ?? self.lastReadSeq
        )
        self.isClosed = data["isClosed"] as? Bool ?? false
        self.updatedAt = Self.dateValue(data["updatedAt"])
    }

    private static func dateValue(_ raw: Any?) -> Date? {
        if let timestamp = raw as? Timestamp {
            return timestamp.dateValue()
        }
        return raw as? Date
    }

    private static func int64Value(_ raw: Any?) -> Int64? {
        if let number = raw as? NSNumber { return number.int64Value }
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? UInt64 {
            return value > UInt64(Int64.max) ? Int64.max : Int64(value)
        }
        if let value = raw as? Double { return Int64(value) }
        if let value = raw as? String, let parsed = Int64(value) { return parsed }
        return nil
    }
}

struct JoinedRoomListItem: Equatable {
    let room: ChatRoom
    let projection: JoinedRoomProjection

    var roomID: String {
        projection.roomID
    }

    func readSnapshot() -> ChatRoomReadSnapshot {
        ChatRoomReadSnapshot(
            roomID: roomID,
            latestSeq: room.seq,
            latestUnreadMessageSeq: room.unreadMessageSeq,
            lastReadSeq: projection.lastReadSeq,
            lastReadUnreadMessageSeq: projection.lastReadUnreadMessageSeq,
            lastMessageSenderUID: room.lastMessageSenderUID,
            latestMessagePreview: room.lastMessage,
            latestMessageAt: room.lastMessageAt
        )
    }
}
