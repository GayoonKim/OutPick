//
//  MediaStorageLocation.swift
//  OutPick
//
//  Created by 김가윤 on 1/14/25.
//

import Foundation

/// Firebase Storage(또는 유사 스토리지)에서 저장 위치를 나타내는 용도
enum ImageLocation {
    case profileImage
    case roomImage
    case video

    /// 최상위 폴더명(기존 location 프로퍼티)
    var folderName: String {
        switch self {
        case .profileImage: return "Users"
        case .roomImage:    return "Rooms"
        case .video:        return "Videos"
        }
    }
}
