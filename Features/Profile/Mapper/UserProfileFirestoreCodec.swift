//
//  UserProfileFirestoreCodec.swift
//  OutPick
//

import Foundation
import FirebaseFirestore

/// DTO <-> Firestore 문서(Dictionary) 변환
enum UserProfileFirestoreCodec {

    private static let iso = ISO8601DateFormatter()

    // Firestore 필드 키를 한 곳에서만 관리
    private enum Key {
        static let deviceID = "deviceID"
        static let email = "email"
        static let gender = "gender"
        static let birthdate = "birthdate"
        static let nickname = "nickname"
        static let thumbPath = "thumbPath"
        static let originalPath = "originalPath"
        static let joinedRooms = "joinedRooms"

        // createdAt 정책
        static let createdAt = "createdAt"                 // Timestamp
        static let createdAtISO8601 = "createdAtISO8601"   // String
    }

    /// DTO -> Firestore 문서(Dictionary)
    /// - Important: createdAt을 서버시간으로 쓰려면 Repository에서 FieldValue.serverTimestamp()를 넣는 게 보통 더 깔끔함.
    static func toDocument(_ dto: UserProfileDTO) -> [String: Any] {
        var dict: [String: Any] = [:]

        dict[Key.deviceID] = dto.deviceID ?? ""
        dict[Key.email] = dto.email
        dict[Key.gender] = dto.gender ?? ""
        dict[Key.birthdate] = dto.birthdate ?? ""
        dict[Key.nickname] = dto.nickname ?? ""
        dict[Key.thumbPath] = dto.thumbPath ?? ""
        dict[Key.originalPath] = dto.originalPath ?? ""
        dict[Key.joinedRooms] = dto.joinedRooms ?? []

        // 클라 복원용 ISO도 같이 보관(선택)
        if let isoString = dto.createdAtISO8601 {
            dict[Key.createdAtISO8601] = isoString
        }

        return dict
    }

    /// Firestore 문서(Dictionary) -> DTO
    /// - Parameters:
    ///   - emailFallback: 문서에 email 필드가 없을 때(혹은 문서 ID가 email일 때) 채워넣기용
    static func fromDocument(_ data: [String: Any], emailFallback: String) -> UserProfileDTO {

        let email = (data[Key.email] as? String) ?? emailFallback

        let deviceID = data[Key.deviceID] as? String
        let gender = data[Key.gender] as? String
        let birthdate = data[Key.birthdate] as? String
        let nickname = data[Key.nickname] as? String
        let thumbPath = data[Key.thumbPath] as? String
        let originalPath = data[Key.originalPath] as? String
        let joinedRooms = data[Key.joinedRooms] as? [String]

        // createdAt 복원 우선순위:
        // 1) Timestamp -> ISO로 변환
        // 2) createdAtISO8601 문자열
        var createdAtISO: String? = data[Key.createdAtISO8601] as? String
        if let ts = data[Key.createdAt] as? Timestamp {
            createdAtISO = iso.string(from: ts.dateValue())
        }

        return UserProfileDTO(
            deviceID: deviceID,
            email: email,
            gender: gender,
            birthdate: birthdate,
            nickname: nickname,
            thumbPath: thumbPath,
            originalPath: originalPath,
            joinedRooms: joinedRooms,
            createdAtISO8601: createdAtISO
        )
    }
}
