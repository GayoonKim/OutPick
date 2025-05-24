//
//  UserProfilesStoreManager.swift
//  OutPick
//
//  Created by 김가윤 on 5/17/25.
//

import Foundation
import Combine

class ChatUserProfilesStoreManager {
    static let shared = ChatUserProfilesStoreManager()
    private init() {}
    
    private var userProfilesByRoomName: [String: [UserProfile]] = [:]
    private var profilesSubjects: [String: CurrentValueSubject<[UserProfile], Never>] = [:]
    
    func saveUserProfiles(_ userProfiles: [UserProfile], forRoomName roomName: String) {
        let sorted = userProfiles.sorted { ($0.nickname ?? "") < ($1.nickname ?? "") }
        
        if let subject = profilesSubjects[roomName] {
            subject.send(sorted)
        } else {
            profilesSubjects[roomName] = CurrentValueSubject<[UserProfile], Never>(sorted)
        }
    }
    
    func appendUserProfile(_ userProfile: UserProfile, forRoomName roomName: String) {
        let subject = profilesSubjects[roomName] ?? CurrentValueSubject<[UserProfile], Never>([])
        var current = subject.value
        
        if current.contains(where: { $0.email == userProfile.email }) { return }
        
        current.append(userProfile)
        current.sort { ($0.nickname ?? "") < ($1.nickname ?? "") }
        subject.send(current)
    
        profilesSubjects[roomName] = subject
    }
    
    func getUserProfiles(forRoomName roomName: String) -> [UserProfile] {
        return profilesSubjects[roomName]?.value ?? []
    }
    
    func hasProfiles(forRoomName roomName: String) -> Bool {
        return !(profilesSubjects[roomName]?.value.isEmpty ?? true)
    }
    
    func countProfiles(forRoomName roomName: String) -> Int {
        return getUserProfiles(forRoomName: roomName).count
    }
    
    func profilesPublisher(forRoomName roomName: String) -> AnyPublisher<[UserProfile], Never> {
        return profilesSubjects[roomName, default: CurrentValueSubject([])].eraseToAnyPublisher()
    }
}
