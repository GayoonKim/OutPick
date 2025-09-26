//
//  Attachment.swift
//  OutPick
//
//  Created by 김가윤 on 12/28/24.
//

//import UIKit
//
//// 첨부 파일 정보
//struct Attachment: Codable {
//    enum AttachmentType: String, Codable {
//        case image
//        case video
//        // 필요한 경우 더 추가
//    }
//    
//    let type: AttachmentType
//    var fileName: String?
//    var fileData: Data?
//
//    func toDict() -> [String: Any] {
//        var dict: [String: Any] = [
//            "type": type.rawValue,
//            "fileName": fileName ?? ""
//        ]
//        // For Socket.IO payloads we send thumbnails as `thumbData` (Data or base64 at transport)
//        if let data = fileData {
//            dict["thumbData"] = data
//        }
//        return dict
//    }
//}
//
//
//extension Attachment: Equatable {
//    static func == (lhs: Attachment, rhs: Attachment) -> Bool {
//        return lhs.type == rhs.type &&
//               lhs.fileName == rhs.fileName
//    }
//}
//
//extension Attachment: Hashable {
//    func hash(into hasher: inout Hasher) {
//        hasher.combine(type)
//        hasher.combine(fileName ?? "")
//    }
//}
//
//extension Attachment {
//    func toUIImage() -> UIImage? {
//        guard type == .image, let data = fileData else { return nil }
//        return UIImage(data: data)
//    }
//}
