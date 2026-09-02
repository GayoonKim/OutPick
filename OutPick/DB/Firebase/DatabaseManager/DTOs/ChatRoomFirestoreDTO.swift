//
//  ChatRoomFirestoreDTO.swift
//  OutPick
//
//  Created by Codex on 7/14/26.
//

import Foundation

struct ChatRoomFirestoreDTO: Decodable {
    let roomName: String
    let roomDescription: String?
    let participantUIDs: [String]?
    let ownerUID: String?
    let creatorUID: String?
    let createdAt: Date
    let thumbPath: String?
    let originalPath: String?
    let lastMessageAt: Date?
    let lastMessage: String?
    let lastMessageSenderUID: String?
    let memberCount: Int?
    let seq: Int64?
    let unreadMessageSeq: Int64?
    let isClosed: Bool?
    let lifecycleStatus: String?
    let lifecycleVersion: Int?
    let closureNoticeCode: String?
    let closedAt: Date?
    let activeAnnouncementID: String?
    let activeAnnouncement: AnnouncementPayload?
    let announcementUpdatedAt: Date?
}
