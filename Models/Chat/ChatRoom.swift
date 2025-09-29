//
//  Room.swift
//  OutPick
//
//  Created by 김가윤 on 9/25/24.
//

import Foundation
import FirebaseFirestore
/// 방 상단 배너에 표시할 간단한 공지 페이로드
struct AnnouncementPayload: Codable, Hashable {
    /// 공지 본문(필수)
    let text: String
    /// 작성자 ID(이메일 등 식별자)
    let authorID: String
    /// 생성 시각(배너 정렬/만료 로직 등에 활용)
    let createdAt: Date
}

extension AnnouncementPayload {
    /// Firestore 저장용 딕셔너리 변환(수동 저장 시 사용)
    func toDictionary() -> [String: Any] {
        return [
            "text": text,
            "authorID": authorID,
            "createdAt": Timestamp(date: createdAt)
        ]
    }
}

struct ChatRoom: Codable {
    
    @DocumentID var ID: String?
    var roomName: String                // 방 이름
    var roomDescription: String         // 방 주제 및 설명
    var participants: [String]          // 방 참여 사용자들
    let creatorID: String               // 방 생성자 ID
    let createdAt: Date                 // 방 생성 시간
    var roomImagePath: String?           // Firestore Storage에 이미지 저장
    var lastMessageAt: Date?
    var lastMessage: String?
    
    // 현재 방의 활성 공지(배너) 상태
    var activeAnnouncementID: String?       // 메시지 히스토리(.announcement) 문서 ID
    var activeAnnouncement: AnnouncementPayload? // 빠른 렌더를 위한 디노말라이즈 사본
    var announcementUpdatedAt: Date?        // 표시/정렬용 타임스탬프
    
    enum CodingKeys: String, CodingKey {
        case ID
        case roomName
        case roomDescription
        case participants = "participantIDs"  // 매핑
        case creatorID
        case createdAt
        case roomImagePath
        case lastMessageAt
        case lastMessage
        case activeAnnouncementID
        case activeAnnouncement
        case announcementUpdatedAt
    }
    
    // Firestore에 저장하기 위힌 뱐환 메서드
    func toDictionary() -> [String: Any] {
        var data: [String: Any] = [
            "ID": ID ?? "",
            "roomName": roomName,
            "roomDescription": roomDescription,
            "participantIDs": participants,
            "creatorID": creatorID,
            "createdAt": Timestamp(date: createdAt),
            "roomImagePath": roomImagePath ?? "",
            "lastMessageAt": Timestamp(date: lastMessageAt ?? createdAt)
        ]
        
        // 선택 필드는 있을 때만 저장하여 Firestore 문서 깔끔하게 유지
        if let roomImagePath = roomImagePath { data["roomImagePath"] = roomImagePath }
        if let activeAnnouncementID = activeAnnouncementID { data["activeAnnouncementID"] = activeAnnouncementID }
        if let activeAnnouncement = activeAnnouncement {
            data["activeAnnouncement"] = activeAnnouncement.toDictionary()
            data["announcementUpdatedAt"] = Timestamp(date: activeAnnouncement.createdAt)
        } else if let announcementUpdatedAt = announcementUpdatedAt {
            data["announcementUpdatedAt"] = Timestamp(date: announcementUpdatedAt)
        }
        
        
        return data
    }
    
}

extension ChatRoom: Hashable {
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ID)
    }
    
    static func == (lhs: ChatRoom, rhs: ChatRoom) -> Bool {
        return lhs.ID == rhs.ID
    }
}
