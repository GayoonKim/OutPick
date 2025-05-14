//
//  Attachment.swift
//  OutPick
//
//  Created by 김가윤 on 12/28/24.
//

import UIKit

// 첨부 파일 정보
struct Attachment: Codable {
    enum AttachmentType: String, Codable {
        case image
        case video
        // 필요한 경우 더 추가
    }
    
    let type: AttachmentType
    var fileName: String?
    var fileData: Data?
    
    func toDict() -> [String: Any] {
        return [
            "type": type.rawValue,
            "fileName": fileName ?? "",
            "imageData": fileData ?? ""
        ]
    }
}

extension Attachment: Hashable {}

extension Attachment {
    func toUIImage() -> UIImage? {
        guard type == .image, let data = fileData else { return nil }
        return UIImage(data: data)
    }
}
