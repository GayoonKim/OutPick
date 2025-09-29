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
    var thumbPath: String?
    var originalPath: String?
    var joinedRooms: [String]
    let createdAt: Date

    init(
        email: String?,
        nickname: String?,
        gender: String?,
        birthdate: String?,
        thumbPath: String?,
        originalPath: String?,
        joinedRooms: [String]?
    ) {
        self.email = email
        self.nickname = nickname
        self.gender = gender
        self.birthdate = birthdate
        self.thumbPath = thumbPath
        self.originalPath = originalPath
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
            "thumbPath": thumbPath ?? "",
            "originalPath": originalPath ?? "",
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
