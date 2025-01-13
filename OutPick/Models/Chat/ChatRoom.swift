//
//  Room.swift
//  OutPick
//
//  Created by 김가윤 on 9/25/24.
//

import Foundation
import FirebaseFirestore

struct ChatRoom: Codable {
    
    var id: String?
    var roomName: String                // 방 이름
    var roomDescription: String         // 방 주제 및 설명
    var participants: [String]          // 방 참여 사용자들
    let creatorID: String               // 방 생성자 ID
    let createdAt: Date                 // 방 생성 시간
    var roomImageName: String?           // Firestore Storage에 이미지 저장
    
    // Firestore에 저장하기 위힌 뱐환 메서드
    func toDictionary() -> [String: Any] {
        let data: [String: Any] = [
            "id": UUID().uuidString,
            "roomName": roomName,
            "roomDescription": roomDescription,
            "participantIDs": participants,
            "creatorID": creatorID,
            "createdAt": Timestamp(date: createdAt),
            "roomImageName": roomImageName ?? ""
        ]
        
        return data
    }
    
}

extension ChatRoom: Hashable {
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ChatRoom, rhs: ChatRoom) -> Bool {
        return lhs.id == rhs.id
    }
    
    static func < (lhs: ChatRoom, rhs: ChatRoom) -> Bool {
        let lhsDate = lhs.createdAt.addingTimeInterval(100)
        let rhsDate = rhs.createdAt.addingTimeInterval(100)
        
        return lhsDate < rhsDate
    }
}
