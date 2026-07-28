import Foundation

protocol UserPublicProfileRepositoryProtocol {
    func fetchProfile(userID: String) async throws -> UserPublicProfile
    func fetchProfiles(userIDs: [String]) async throws -> [String: UserPublicProfile]
}
