//
//  UserProfilesStoreManager.swift
//  OutPick
//
//  Created by 김가윤 on 5/17/25.
//

import Foundation

class ChatUserProfilesStoreManager {
    static let shared = ChatUserProfilesStoreManager()
    private init() {}
    
    private var userProfilesByRoomName: [String: [UserProfile]] = [:]
    
    func saveUserProfiles(_ userProfiles: [UserProfile], forRoomName roomName: String) {
        userProfilesByRoomName[roomName] = userProfiles
    }
    
    func getUserProfiles(forRoomName roomName: String) -> [UserProfile] {
        return userProfilesByRoomName[roomName] ?? []
    }
    
    func hasProfiles(for roomName: String) -> Bool {
        return userProfilesByRoomName[roomName] != nil
    }
    
    func countProfiles(for roomName: String) -> Int {
        return getUserProfiles(forRoomName: roomName).count
    }
}
