//
//  ChatRoomFirestoreMapper.swift
//  OutPick
//
//  Created by Codex on 7/14/26.
//

import Foundation
import FirebaseFirestore

enum ChatRoomFirestoreMappingError: Error, Equatable {
    case missingDocumentID
    case emptyRoomName
    case emptyOwnerUID
}

enum ChatRoomFirestoreMapper {
    static func map(
        dto: ChatRoomFirestoreDTO,
        documentID: String
    ) throws -> ChatRoom {
        let id = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw ChatRoomFirestoreMappingError.missingDocumentID
        }

        guard !dto.roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatRoomFirestoreMappingError.emptyRoomName
        }
        let ownerUID = (dto.ownerUID ?? dto.creatorUID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ownerUID.isEmpty else {
            throw ChatRoomFirestoreMappingError.emptyOwnerUID
        }

        let participants = dto.participantUIDs ?? []
        return ChatRoom(
            id: id,
            roomName: dto.roomName,
            roomDescription: dto.roomDescription ?? "",
            participants: participants,
            ownerUID: ownerUID,
            createdAt: dto.createdAt,
            thumbPath: dto.thumbPath,
            originalPath: dto.originalPath,
            lastMessageAt: dto.lastMessageAt,
            lastMessage: dto.lastMessage,
            lastMessageSenderUID: dto.lastMessageSenderUID,
            memberCount: dto.memberCount ?? participants.count,
            seq: dto.seq ?? 0,
            unreadMessageSeq: dto.unreadMessageSeq ?? dto.seq ?? 0,
            isClosed: dto.isClosed ?? false,
            closureType: dto.lifecycleStatus.flatMap(ChatRoomClosureType.init(rawValue:)),
            lifecycleVersion: dto.lifecycleVersion ?? 1,
            closureNoticeCode: dto.closureNoticeCode,
            closedAt: dto.closedAt,
            activeAnnouncementID: dto.activeAnnouncementID,
            activeAnnouncement: dto.activeAnnouncement,
            announcementUpdatedAt: dto.announcementUpdatedAt
        )
    }

    static func creationData(from room: ChatRoom) -> [String: Any] {
        let searchIndex = ChatRoomSearchIndex.buildIndexedFields(
            roomName: room.roomName,
            roomDescription: room.roomDescription
        )
        var data: [String: Any] = [
            "roomName": room.roomName,
            "roomDescription": room.roomDescription,
            // 최소 지원 버전 전환 전까지 기존 서버·앱과 호환되는 생성 key를 유지한다.
            "creatorUID": room.ownerUID,
            "createdAt": Timestamp(date: room.createdAt),
            "lastMessageAt": Timestamp(date: room.lastMessageAt ?? room.createdAt),
            "memberCount": max(1, room.memberCount),
            "seq": room.seq,
            "isClosed": room.isClosed,
            "lifecycleStatus": "active",
            "lifecycleVersion": max(1, room.lifecycleVersion),
            "roomSearchNormalized": searchIndex.normalizedText,
            "roomSearchChars": searchIndex.searchChars,
            "roomSearchNgrams2": searchIndex.searchNgrams2,
            "roomSearchIndexVersion": searchIndex.version,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let lastMessage = room.lastMessage, !lastMessage.isEmpty {
            data["lastMessage"] = lastMessage
        }
        if let lastMessageSenderUID = room.lastMessageSenderUID, !lastMessageSenderUID.isEmpty {
            data["lastMessageSenderUID"] = lastMessageSenderUID
        }
        if let thumbPath = room.thumbPath, !thumbPath.isEmpty {
            data["thumbPath"] = thumbPath
        }
        if let originalPath = room.originalPath, !originalPath.isEmpty {
            data["originalPath"] = originalPath
        }
        if let activeAnnouncementID = room.activeAnnouncementID {
            data["activeAnnouncementID"] = activeAnnouncementID
        }
        if let announcement = room.activeAnnouncement {
            data["activeAnnouncement"] = announcementData(announcement)
            data["announcementUpdatedAt"] = Timestamp(date: announcement.createdAt)
        } else if let announcementUpdatedAt = room.announcementUpdatedAt {
            data["announcementUpdatedAt"] = Timestamp(date: announcementUpdatedAt)
        }

        return data
    }

    static func announcementData(_ announcement: AnnouncementPayload) -> [String: Any] {
        var data: [String: Any] = [
            "text": announcement.text,
            "authorID": announcement.authorID,
            "createdAt": Timestamp(date: announcement.createdAt)
        ]
        if let authorUID = announcement.authorUID, !authorUID.isEmpty {
            data["authorUID"] = authorUID
        }
        return data
    }
}
