import FirebaseFirestore
import Foundation

final class FirestoreStyleMoodRepository: StyleMoodRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore) {
        self.db = db
    }

    func fetchOnboardingMoods() async throws -> [StyleMood] {
        let snapshot = try await db.collection("styleMoods")
            .whereField("status", isEqualTo: "active")
            .order(by: "sortOrder")
            .getDocuments()

        return snapshot.documents
            .compactMap { document in
                StyleMoodDTO(id: document.documentID, data: document.data())?.toDomain()
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.id < $1.id
            }
    }
}
