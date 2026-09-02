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
    let authorUID: String?
    let createdAt: Date

    init(text: String, authorID: String, authorUID: String? = nil, createdAt: Date) {
        self.text = text
        self.authorID = authorID
        self.authorUID = authorUID
        self.createdAt = createdAt
    }
}

struct ChatRoom {
    let id: String
    var roomName: String
    var roomDescription: String
    var participants: [String]
    let ownerUID: String
    let createdAt: Date
    var thumbPath: String?
    var originalPath: String?
    var lastMessageAt: Date?
    var lastMessage: String?
    var lastMessageSenderUID: String?
    var memberCount: Int = 0

    /// 방의 현재 tail 시퀀스 값입니다.
    var seq: Int64 = 0

    /// 실제 안읽음 대상 메시지만 증가하는 별도 시퀀스입니다.
    var unreadMessageSeq: Int64 = 0

    /// 방이 종료된 상태인지 나타냅니다.
    var isClosed: Bool = false

    /// 종료 tombstone이 보존하는 종료 주체입니다.
    var closureType: ChatRoomClosureType?

    /// 서버 room lifecycle의 낙관적 잠금 버전입니다.
    var lifecycleVersion: Int = 1

    var closureNoticeCode: String?
    var closedAt: Date?

    var activeAnnouncementID: String?
    var activeAnnouncement: AnnouncementPayload?
    var announcementUpdatedAt: Date?

    init(
        id: String,
        roomName: String,
        roomDescription: String,
        participants: [String],
        ownerUID: String,
        createdAt: Date,
        thumbPath: String? = nil,
        originalPath: String? = nil,
        lastMessageAt: Date? = nil,
        lastMessage: String? = nil,
        lastMessageSenderUID: String? = nil,
        memberCount: Int = 0,
        seq: Int64 = 0,
        unreadMessageSeq: Int64 = 0,
        isClosed: Bool = false,
        closureType: ChatRoomClosureType? = nil,
        lifecycleVersion: Int = 1,
        closureNoticeCode: String? = nil,
        closedAt: Date? = nil,
        activeAnnouncementID: String? = nil,
        activeAnnouncement: AnnouncementPayload? = nil,
        announcementUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.roomName = roomName
        self.roomDescription = roomDescription
        self.participants = participants
        self.ownerUID = ownerUID
        self.createdAt = createdAt
        self.thumbPath = thumbPath
        self.originalPath = originalPath
        self.lastMessageAt = lastMessageAt
        self.lastMessage = lastMessage
        self.lastMessageSenderUID = lastMessageSenderUID
        self.memberCount = memberCount
        self.seq = seq
        self.unreadMessageSeq = unreadMessageSeq
        self.isClosed = isClosed
        self.closureType = closureType
        self.lifecycleVersion = lifecycleVersion
        self.closureNoticeCode = closureNoticeCode
        self.closedAt = closedAt
        self.activeAnnouncementID = activeAnnouncementID
        self.activeAnnouncement = activeAnnouncement
        self.announcementUpdatedAt = announcementUpdatedAt
    }

    /// `creatorUID` 제거 전 소스 호환을 위한 임시 생성자입니다.
    init(
        id: String,
        roomName: String,
        roomDescription: String,
        participants: [String],
        creatorUID: String,
        createdAt: Date,
        thumbPath: String? = nil,
        originalPath: String? = nil,
        lastMessageAt: Date? = nil,
        lastMessage: String? = nil,
        lastMessageSenderUID: String? = nil,
        memberCount: Int = 0,
        seq: Int64 = 0,
        unreadMessageSeq: Int64 = 0,
        isClosed: Bool = false,
        closureType: ChatRoomClosureType? = nil,
        lifecycleVersion: Int = 1,
        closureNoticeCode: String? = nil,
        closedAt: Date? = nil,
        activeAnnouncementID: String? = nil,
        activeAnnouncement: AnnouncementPayload? = nil,
        announcementUpdatedAt: Date? = nil
    ) {
        self.init(
            id: id,
            roomName: roomName,
            roomDescription: roomDescription,
            participants: participants,
            ownerUID: creatorUID,
            createdAt: createdAt,
            thumbPath: thumbPath,
            originalPath: originalPath,
            lastMessageAt: lastMessageAt,
            lastMessage: lastMessage,
            lastMessageSenderUID: lastMessageSenderUID,
            memberCount: memberCount,
            seq: seq,
            unreadMessageSeq: unreadMessageSeq,
            isClosed: isClosed,
            closureType: closureType,
            lifecycleVersion: lifecycleVersion,
            closureNoticeCode: closureNoticeCode,
            closedAt: closedAt,
            activeAnnouncementID: activeAnnouncementID,
            activeAnnouncement: activeAnnouncement,
            announcementUpdatedAt: announcementUpdatedAt
        )
    }

    /// 최소 지원 버전 전환이 끝날 때 제거할 소스 호환 별칭입니다.
    var creatorUID: String { ownerUID }

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
