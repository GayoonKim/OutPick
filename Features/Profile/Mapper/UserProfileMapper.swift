//
//  UserProfileMapper.swift
//  OutPick
//

import Foundation

/// Domain <-> DTO 변환 전용
enum UserProfileMapper {

    private static let iso = ISO8601DateFormatter()

    /// Domain -> DTO
    static func toDTO(_ domain: UserProfile) -> UserProfileDTO {
        return UserProfileDTO(
            deviceID: domain.deviceID,
            email: domain.email ?? "", // 도메인 email이 Optional이라 안전 처리
            gender: domain.gender,
            birthdate: domain.birthdate,
            nickname: domain.nickname,
            thumbPath: domain.thumbPath,
            originalPath: domain.originalPath,
            joinedRooms: domain.joinedRooms,
            createdAtISO8601: iso.string(from: domain.createdAt)
        )
    }

    /// DTO -> Domain
    /// - Note: joinedRooms는 Domain에서 non-optional이므로 기본값 [] 처리
    /// - Note: createdAtISO8601이 없거나 파싱 실패면 Date()로 대체 (확실하지 않음: 정책은 팀/서비스 기준으로 결정)
    static func toDomain(_ dto: UserProfileDTO) -> UserProfile {
        let createdAt: Date
        if let s = dto.createdAtISO8601, let d = iso.date(from: s) {
            createdAt = d
        } else {
            createdAt = Date()
        }

        return UserProfile(
            deviceID: dto.deviceID,
            email: dto.email,
            gender: dto.gender,
            birthdate: dto.birthdate,
            nickname: dto.nickname,
            thumbPath: dto.thumbPath,
            originalPath: dto.originalPath,
            joinedRooms: dto.joinedRooms ?? [],
            createdAt: createdAt
        )
    }
}
