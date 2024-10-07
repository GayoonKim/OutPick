//
//  UserProfile.swift
//  OutPick
//
//  Created by 김가윤 on 8/8/24.
//

import UIKit

struct UserProfile: Codable {
    
    static var sharedUserProfile = UserProfile()
    
    var gender: String?
    var birthdate: String?
    var nickname: String?
    var profileImageURL: String? // Firestore에 이미지를 직접 저장할 수 없기 때문에 Firestore Storage에 이미지 저장
    var joinedRooms: [String]?

}

extension UserProfile {
    
    // Firestore에 저장하기 위해 딕셔너리 형태로 변환
    func toDict() -> [String: Any] {
        return [
            "nickname": nickname ?? "",
            "gender": gender ?? "",
            "birthdate": birthdate ?? "",
            "profileImageURL": profileImageURL ?? "",
            "joinedRooms": joinedRooms ?? []
        ]
    }
    
}
