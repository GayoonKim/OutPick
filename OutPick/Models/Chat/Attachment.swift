//
//  Attachment.swift
//  OutPick
//
//  Created by 김가윤 on 12/28/24.
//

import UIKit

// 첨부 파일 정보
struct Attachment {
    
    let id: String
    let type: AttachmentType
    let url: String
    let size: Int64?
    let fileName: String?
    
    func toDict() -> [String: Any] {
        
        return [
            "id": UUID().uuidString
        ]
        
    }
    
    enum AttachmentType: String, Codable {
        
        case image
        case video
        case file
        
    }
    
}
