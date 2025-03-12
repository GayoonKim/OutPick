//
//  Attachment.swift
//  OutPick
//
//  Created by 김가윤 on 12/28/24.
//

import UIKit

// 첨부 파일 정보
struct Attachment: Codable {
    let type: String
    let fileName: String
    
    func toDict() -> [String: Any] {
        return [
            "type": type,
            "fileName": fileName 
        ]
    }
}
