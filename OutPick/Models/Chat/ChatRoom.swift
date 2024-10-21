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
    var participants: [UserProfile]     // 방 참여 사용자들
    let creatorID: String               // 방 생성자 ID
    let createdAt: Date                 // 방 생성 시간
    var lastMessage: ChatMessage?       // 마지막 메시지
    var roomImageURL: String?           // Firestore Storage에 이미지 저장
    
    // Firestore에 저장하기 위힌 뱐환 메서드
    func toDictionary() -> [String: Any] {
        var data: [String: Any] = [
            "id": UUID().uuidString,
            "roomName": roomName,
            "roomDescription": roomDescription,
            "creatorID": creatorID,
            "createdAt": createdAt,
            "roomImageURL": roomImageURL ?? ""
        ]
        
        // participants를 Firestore에 저장하기 위해 Dictionary로 변환
        data["participants"] = participants.map { $0.toDict() }
        
        // lastMessage가 존재할 경우, 이를 Dictionary로 변환
        if let lastMessage = lastMessage {
            data["lastMesage"] = lastMessage.toDictionary()
        }
        
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
        guard let lhsDate = lhs.lastMessage?.sentAt.addingTimeInterval(100),
              let rhsDate = rhs.lastMessage?.sentAt.addingTimeInterval(100) else {
            return false
        }
        
        return lhsDate < rhsDate
    }
}
