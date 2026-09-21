import Foundation

/// 기존 프로필 조회 결과를 캐시 무효화에 전달한다. 추가 서버 조회는 하지 않는다.
final class AvatarObservingPublicProfileRepository: UserPublicProfileRepositoryProtocol {
    private let base: UserPublicProfileRepositoryProtocol
    private let images: AvatarImageManaging
    init(base: UserPublicProfileRepositoryProtocol, images: AvatarImageManaging) {
        self.base = base
        self.images = images
    }
    func fetchProfile(userID: String) async throws -> UserPublicProfile {
        let token = await images.avatarSessionToken()
        let profile = try await base.fetchProfile(userID: userID)
        guard let current = await images.observeAvatarProfile(profile, previous: nil, token: token) else { throw CancellationError() }
        return current
    }
    func fetchProfiles(userIDs: [String]) async throws -> [String: UserPublicProfile] {
        let token = await images.avatarSessionToken()
        let profiles = try await base.fetchProfiles(userIDs: userIDs)
        var result: [String: UserPublicProfile] = [:]
        for (id, profile) in profiles {
            guard let current = await images.observeAvatarProfile(profile, previous: nil, token: token) else { throw CancellationError() }
            result[id] = current
        }
        guard token == (await images.avatarSessionToken()), token != nil else { throw CancellationError() }
        return result
    }
}
