//
//  Message.swift
//  OutPick
//
//  Created by 김가윤 on 9/25/24.
//

import Foundation

// 채팅 메시지 정보
struct ChatMessage: Codable {
    
    let messageID: String                // 메시지 고유 ID
    let senderID: String                 // 메시지 전송 사용자 아이디
    let senderNickname: String           // 메시지 전송 사용자 닉네임
    let msg: String                      // 메시지 내용
    let sentAt: Date                     // 메시지 보낸 시간
    let messageType: MessageType         // 텍스트, 이미지, 비디오 등
    
    
    // Firestore에 저장하기 위힌 뱐환 메서드
    func toDictionary() -> [String: Any] {
        return [
            "messageID": UUID().uuidString,
            "senderID": senderID,
            "senderNickname": senderNickname,
            "content": msg,
            "sentAt": sentAt,
            "messageType": messageType
        ]
    }
    
}

enum MessageType: Codable {
    case Text, Image, Video
}

extension ChatMessage: Hashable {}
