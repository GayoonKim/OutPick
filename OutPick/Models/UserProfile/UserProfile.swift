//
//  UserProfile.swift
//  OutPick
//
//  Created by 김가윤 on 8/8/24.
//

import UIKit
import FirebaseFirestore

class UserProfile: Codable {
    
    static var shared = UserProfile()
    
    var deviceID: String?
    var email: String?
    var gender: String?
    var birthdate: String?
    var nickname: String?
    var profileImageName: String? // Firestore에 이미지를 직접 저장할 수 없기 때문에 Firestore Storage에 이미지 저장
    var joinedRooms: [String]?
    let createdAt: Date
    
    private init() {
        self.createdAt = Date()
    }
    
    init(email: String?, nickname: String?, gender: String?, birthdate: String?, profileImageName: String?, joinedRooms: [String]?) {
        self.email = email
        self.nickname = nickname
        self.gender = gender
        self.birthdate = birthdate
        self.profileImageName = profileImageName
        self.joinedRooms = joinedRooms
        self.createdAt = Date()
    }

}

extension UserProfile {
    
    // Firestore에 저장하기 위해 딕셔너리 형태로 변환
    func toDict() -> [String: Any] {
        
        return [
            
            "deviceID": deviceID ?? "",
            "email": email ?? "",
            "nickname": nickname ?? "",
            "gender": gender ?? "",
            "birthdate": birthdate ?? "",
            "profileImageName": profileImageName ?? "",
            "joinedRooms": joinedRooms ?? [],
            "createdAt": Timestamp(date: createdAt)
            
        ]
    }
    
}

extension UserProfile: Hashable {
    static func == (lhs: UserProfile, rhs: UserProfile) -> Bool {
        return lhs.email == rhs.email
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(email)
    }
}
