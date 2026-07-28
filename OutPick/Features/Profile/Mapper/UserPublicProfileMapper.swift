import Foundation

enum UserPublicProfileMapper {
    static func toDomain(_ dto: UserPublicProfileDTO) -> UserPublicProfile {
        UserPublicProfile(
            userID: dto.userID,
            nickname: dto.nickname,
            avatarThumbPath: dto.avatarThumbPath,
            avatarOriginalPath: dto.avatarOriginalPath,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}
