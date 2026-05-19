//
//  UserProfileDTO.swift
//  OutPick
//

import Foundation

/// DTO: 저장소/네트워크 계층에서 사용하는 전송 모델
/// - Note: createdAt은 ISO8601 문자열 형태로 들고 다니는 것을 기본으로 함
struct UserProfileDTO: Codable, Equatable {
    var deviceID: String?
    var email: String          // DTO에서는 필수로 두는 걸 권장
    var gender: String?
    var birthdate: String?
    var nickname: String?
    var thumbPath: String?
    var originalPath: String?
    var joinedRooms: [String]?
    var createdAtISO8601: String?

    init(
        deviceID: String? = nil,
        email: String,
        gender: String? = nil,
        birthdate: String? = nil,
        nickname: String? = nil,
        thumbPath: String? = nil,
        originalPath: String? = nil,
        joinedRooms: [String]? = nil,
        createdAtISO8601: String? = nil
    ) {
        self.deviceID = deviceID
        self.email = email
        self.gender = gender
        self.birthdate = birthdate
        self.nickname = nickname
        self.thumbPath = thumbPath
        self.originalPath = originalPath
        self.joinedRooms = joinedRooms
        self.createdAtISO8601 = createdAtISO8601
    }
}
