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
    
    var id: String?
    var gender: String?
    var birthdate: String?
    var nickname: String?
    var profileImageName: String? // Firestore에 이미지를 직접 저장할 수 없기 때문에 Firestore Storage에 이미지 저장
    var joinedRooms: [String]?
    var createdAt: Date
    
    private init() {
        createdAt = Date()
    }

}

extension UserProfile {
    
    // Firestore에 저장하기 위해 딕셔너리 형태로 변환
    func toDict() -> [String: Any] {
        return [
            
            "id": UUID().uuidString,
            "nickname": nickname ?? "",
            "gender": gender ?? "",
            "birthdate": birthdate ?? "",
            "profileImageName": profileImageName ?? "",
            "joinedRooms": joinedRooms ?? "",
            "createdAt": Timestamp(date: createdAt)
            
        ]
    }
    
}
