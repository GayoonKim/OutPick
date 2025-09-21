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

struct ReplyPreview: Codable, Hashable {
    let messageID: String
    var sender: String
    var text: String
    var isDeleted: Bool = false
}

// 채팅 메시지 정보
struct ChatMessage: SocketData, Codable {
    var ID: String = UUID().uuidString
    let roomID: String
    let senderID: String                // 메시지 전송 사용자 아이디
    let senderNickname: String          // 메시지 전송 사용자 닉네임
    let msg: String?                    // 메시지 내용
    let sentAt: Date?                   // 메시지 보낸 시간
    let attachments: [Attachment]
    var replyPreview: ReplyPreview?
    var isFailed: Bool = false

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    enum CodingKeys: String, CodingKey {
        case roomID
        case senderID
        case senderNickname = "senderNickName"
        case msg
        case sentAt
        case attachments
        case replyPreview
    }
    
    func toSocketRepresentation() -> SocketData {
        var dict: [String: Any] = [
            "ID": ID,
            "roomID": roomID,
            "senderID": senderID,
            "senderNickName": senderNickname,
            "msg": msg ?? "",
        ]
        
        dict["attachments"] = attachments.map { $0.toDict() }
        
        if let rp = replyPreview {
            dict["replyPreview"] = [
                "messageID": rp.messageID,
                "sender": rp.sender,
                "text": rp.text,
                "isDeleted": rp.isDeleted
            ]
        }
        
        if let sentAt = sentAt {
            dict["sentAt"] = ChatMessage.iso8601Formatter.string(from: sentAt)
        }
        
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
        ]

        dict["attachments"] = attachments.map { $0.toDict() }
        
        if let rp = replyPreview {
            dict["replyPreview"] = [
                "messageID": rp.messageID,
                "sender": rp.sender,
                "text": rp.text,
                "isDeleted": rp.isDeleted
            ]
        }
        
        return dict
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(ID) }
    static func ==(lhs: ChatMessage, rhs: ChatMessage) -> Bool { lhs.ID == rhs.ID }
}

extension ChatMessage: Hashable {}
