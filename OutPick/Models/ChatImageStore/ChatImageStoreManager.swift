//
//  ChatImageStoreManager.swift
//  OutPick
//
//  Created by 김가윤 on 5/14/25.
//

import UIKit

class ChatImageStoreManager {
    static let shared = ChatImageStoreManager()
    private init() {}
    
    private var imagesByRoomName: [String: [UIImage]] = [:]
    
    func addImages(_ images: [UIImage], for roomName: String) {
        imagesByRoomName[roomName, default: []].append(contentsOf: images)
    }
    
    func getImages(for roomName: String) -> [UIImage] {
        return imagesByRoomName[roomName] ?? []
    }
    
    func isEmpty(for roomName: String) -> Bool {
        guard let _ = imagesByRoomName[roomName] else {
            return false
        }
        
        return true
    }
    
    func count(for roomName: String) -> Int {
        return getImages(for: roomName).count
    }
}
