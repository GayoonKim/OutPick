import FirebaseFirestore
import Foundation

final class FirestoreUserPublicProfileRepository: UserPublicProfileRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore) {
        self.db = db
    }

    func fetchProfile(userID: String) async throws -> UserPublicProfile {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedUserID.isEmpty == false, normalizedUserID.contains("/") == false else {
            throw FirebaseError.FailedToFetchProfile
        }

        let snapshot = try await db.collection("userPublicProfiles")
            .document(normalizedUserID)
            .getDocument()
        guard let data = snapshot.data(),
              let dto = UserPublicProfileDTO(userID: normalizedUserID, data: data) else {
            throw FirebaseError.FailedToFetchProfile
        }
        return UserPublicProfileMapper.toDomain(dto)
    }

    func fetchProfiles(userIDs: [String]) async throws -> [String: UserPublicProfile] {
        let normalizedIDs = Array(Set(userIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.contains("/") == false }))

        return await withTaskGroup(of: (String, UserPublicProfile)?.self) { group in
            for userID in normalizedIDs {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    guard let profile = try? await self.fetchProfile(userID: userID) else {
                        return nil
                    }
                    return (userID, profile)
                }
            }

            var profiles: [String: UserPublicProfile] = [:]
            for await result in group {
                if let (userID, profile) = result {
                    profiles[userID] = profile
                }
            }
            return profiles
        }
    }
}
