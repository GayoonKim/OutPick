//
//  MediaStorageLocation.swift
//  OutPick
//
//  Created by 김가윤 on 1/14/25.
//

import Foundation

enum ImageLocation: String {
    case ProfileImage
    case RoomImage
    case Video
    
    var location: String {
        switch self {
        case .ProfileImage:
            "Users"
            
        case .RoomImage:
            "Rooms"
            
        case .Video:
            "Videos"
        }
    }
}
