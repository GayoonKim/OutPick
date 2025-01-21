//
//  Attachment.swift
//  OutPick
//
//  Created by 김가윤 on 12/28/24.
//

import UIKit

// 첨부 파일 정보
struct Attachment: Codable {
    
    let type: AttachmentType
    let size: Int64?
    let fileName: String?
    let createdAt: Date
    
//    func toDict() -> [String: Any] {
//        
//        return [
//            "id": UUID().uuidString
//        ]
//        
//    }
    
    enum AttachmentType: String, Codable {
        
        case Image
        case Video
        case File
        
        var type: String {
            switch self {
                
            case .Image:
                "Image"
                
            case .Video:
                "Video"
                
            case .File:
                "File"
                
            }
        }
        
    }
    
}
