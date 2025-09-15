//
//  Message.swift
//  OutPick
//
//  Created by 김가윤 on 9/25/24.
//

import UIKit
import FirebaseCore
import SocketIO
import FirebaseFirestore

// 채팅 메시지 정보
struct ChatMessage: SocketData, Codable {
    var ID: String = UUID().uuidString
    let roomID: String
    let senderID: String                // 메시지 전송 사용자 아이디
    let senderNickname: String          // 메시지 전송 사용자 닉네임
    let msg: String?                    // 메시지 내용
    let sentAt: Date?                   // 메시지 보낸 시간
    let attachments: [Attachment]
    let replyTo: String?
    var isFailed: Bool = false

    enum CodingKeys: String, CodingKey {
        case roomID
        case senderID
        case senderNickname = "senderNickName"
        case msg
        case sentAt
        case attachments
        case replyTo
    }
    
    func toSocketRepresentation() -> SocketData {
        var dict: [String: Any] = [
            "ID": ID,
            "roomID": roomID,
            "senderID": senderID,
            "senderNickName": senderNickname,
            "msg": msg ?? "",
            "replyTo": replyTo ?? ""
        ]
        
        dict["attachments"] = attachments.map { $0.toDict() }
        
        return dict
    }
    
    // Firestore에 저장하기 위힌 뱐환 메서드
    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "ID": ID,
            "roomID": roomID,
            "senderID": senderID,
            "senderNickName": senderNickname,
            "msg": msg ?? "",
            "sentAt": Timestamp(date: sentAt ?? Date()),
            "replyTo": replyTo ?? ""
        ]

        dict["attachments"] = attachments.map { $0.toDict() }
        
        return dict
    }
    
//    func hash(into hasher: inout Hasher) { hasher.combine(ID) }
//    static func ==(lhs: ChatMessage, rhs: ChatMessage) -> Bool { lhs.ID == rhs.ID }
}

extension ChatMessage: Hashable {}
