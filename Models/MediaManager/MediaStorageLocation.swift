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
    
    var location: String {
        switch self {
            
        case .ProfileImage:
            "Profile_Images"
            
        case .RoomImage:
            "Room_Images"
            
        }
    }
}

enum VideoLocation: String {
    case Room_Videos
    case Test_Videos
    
    var location: String {
        switch self {
            
        case .Room_Videos:
            "Room_Videos"
            
        case .Test_Videos:
            "Test_Videos"
            
        }
    }
    
}
