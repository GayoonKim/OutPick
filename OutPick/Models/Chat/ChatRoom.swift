//
//  Room.swift
//  OutPick
//
//  Created by 김가윤 on 9/25/24.
//

import Foundation
import FirebaseFirestore

struct ChatRoom: Codable {
    
    var roomName: String                // 방 이름
    var roomDescription: String         // 방 주제 및 설명
    var participants: [UserProfile]     // 방 참여 사용자들
    let creatorID: String               // 방 생성자 ID
    let createdAt: Date                 // 방 생성 시간
    var lastMessage: ChatMessage?       // 마지막 메시지
    
    // Firestore에 저장하기 위힌 뱐환 메서드
    func toDictionary() -> [String: Any] {
        var data: [String: Any] = [
            "roomName": roomName,
            "roomDescription": roomDescription,
            "creatorID": creatorID,
            "createdAt": createdAt,
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