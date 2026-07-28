import FirebaseFirestore
import Foundation

final class FirestoreCurrentUserAccountRepository: CurrentUserAccountRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore) {
        self.db = db
    }

    func fetchAccount(userID: String) async throws -> UserAccount? {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedUserID.isEmpty == false, normalizedUserID.contains("/") == false else {
            throw FirebaseError.FailedToFetchProfile
        }

        let snapshot = try await db.collection("users")
            .document(normalizedUserID)
            .getDocument()
        guard snapshot.exists else { return nil }
        guard let data = snapshot.data(),
              let dto = UserAccountDTO(userID: normalizedUserID, data: data) else {
            throw FirebaseError.FailedToFetchProfile
        }
        return try UserAccountMapper.toDomain(dto)
    }
}
