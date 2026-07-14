//
//  ChatRoom.swift
//  OutPick
//
//  Created by 김가윤 on 9/25/24.
//

import Foundation

/// 방 상단 배너에 표시할 간단한 공지 페이로드
struct AnnouncementPayload: Codable, Hashable {
    let text: String
    let authorID: String
    let createdAt: Date
}

struct ChatRoom {
    let id: String
    var roomName: String
    var roomDescription: String
    var participants: [String]
    let creatorUID: String
    let createdAt: Date
    var thumbPath: String?
    var originalPath: String?
    var lastMessageAt: Date?
    var lastMessage: String?
    var lastMessageSenderUID: String?
    var memberCount: Int = 0

    /// 방의 현재 tail 시퀀스 값입니다.
    var seq: Int64 = 0

    /// 방이 종료된 상태인지 나타냅니다.
    var isClosed: Bool = false

    var activeAnnouncementID: String?
    var activeAnnouncement: AnnouncementPayload?
    var announcementUpdatedAt: Date?

    var coverImagePath: String? {
        if let thumbPath, !thumbPath.isEmpty {
            return thumbPath
        }
        if let originalPath, !originalPath.isEmpty {
            return originalPath
        }
        return nil
    }
}

extension ChatRoom: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChatRoom, rhs: ChatRoom) -> Bool {
        lhs.id == rhs.id
    }
}
