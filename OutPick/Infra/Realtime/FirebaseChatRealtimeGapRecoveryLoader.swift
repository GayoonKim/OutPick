import FirebaseFirestore
import Foundation

final class FirebaseChatRealtimeGapRecoveryLoader: ChatRealtimeGapRecoveryLoading, @unchecked Sendable {
    private let db: Firestore

    init(db: Firestore) {
        self.db = db
    }

    func fetchMessages(
        roomID: String,
        afterSeq: Int64,
        limit: Int
    ) async throws -> [ChatMessage] {
        guard !roomID.isEmpty, limit > 0 else { return [] }

        let snapshot: QuerySnapshot
        do {
            snapshot = try await db
                .collection("Rooms")
                .document(roomID)
                .collection("Messages")
                .whereField("seq", isGreaterThan: afterSeq)
                .order(by: "seq", descending: false)
                .limit(to: limit)
                .getDocuments()
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain {
                if nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                    throw ChatRealtimeGapRecoveryError.permissionDenied
                }
                if nsError.code == FirestoreErrorCode.notFound.rawValue {
                    throw ChatRealtimeGapRecoveryError.roomNotFound
                }
            }
            throw error
        }

        return snapshot.documents.compactMap { document in
            var payload = document.data()
            if payload["ID"] == nil {
                payload["ID"] = document.documentID
            }
            return ChatMessage.from(payload)
        }
    }
}
