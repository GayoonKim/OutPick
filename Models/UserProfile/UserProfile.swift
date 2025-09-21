//
//  UserProfile.swift
//  OutPick
//
//  Created by 김가윤 on 8/8/24.
//

import Foundation
import FirebaseFirestore
import GRDB

struct UserProfile: Codable, Hashable, FetchableRecord, PersistableRecord {
    var deviceID: String?
    var email: String?
    var gender: String?
    var birthdate: String?
    var nickname: String?
    var profileImagePath: String?
    var joinedRooms: [String]
    let createdAt: Date

    init(
        email: String?,
        nickname: String?,
        gender: String?,
        birthdate: String?,
        profileImagePath: String?,
        joinedRooms: [String]?
    ) {
        self.email = email
        self.nickname = nickname
        self.gender = gender
        self.birthdate = birthdate
        self.profileImagePath = profileImagePath
        self.joinedRooms = joinedRooms ?? []
        self.createdAt = Date()
    }

    func toDict() -> [String: Any] {
        return [
            "deviceID": deviceID ?? "",
            "email": email ?? "",
            "nickname": nickname ?? "",
            "gender": gender ?? "",
            "birthdate": birthdate ?? "",
            "profileImagePath": profileImagePath ?? "",
            "joinedRooms": joinedRooms,
            "createdAt": Timestamp(date: createdAt)
        ]
    }

    static func == (lhs: UserProfile, rhs: UserProfile) -> Bool {
        return lhs.email == rhs.email
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(email)
    }
}
