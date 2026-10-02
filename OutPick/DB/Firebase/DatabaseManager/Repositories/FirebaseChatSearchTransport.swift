import Foundation
import FirebaseFirestore

struct FirebaseChatSearchDocument {
    let id: String
    let data: [String: Any]
}

struct FirebaseChatSearchSnapshot {
    let documents: [FirebaseChatSearchDocument]
    let isFromCache: Bool
    let hasPendingWrites: Bool
}

struct FirebaseChatSearchBoundary: Codable, Equatable {
    let seq: Int64
    let documentID: String
}

struct FirebaseChatSearchQuery: Equatable {
    let roomID: String
    let tokenField: String
    let token: String
    let upperSeq: Int64
    let after: FirebaseChatSearchBoundary?
    let limit: Int
}

/// 구현은 서버 source만 사용한다. 테스트는 SDK snapshot 대신 이 경계에 응답을 주입한다.
protocol FirebaseChatSearchTransport {
    func roomFromServer(roomID: String) async throws -> FirebaseChatSearchSnapshot
    func candidatesFromServer(query: FirebaseChatSearchQuery) async throws -> FirebaseChatSearchSnapshot
}

final class FirestoreChatSearchTransport: FirebaseChatSearchTransport {
    private let db: Firestore
    init(db: Firestore) { self.db = db }

    func roomFromServer(roomID: String) async throws -> FirebaseChatSearchSnapshot {
        let snapshot = try await db.collection("Rooms").document(roomID).getDocument(source: .server)
        return FirebaseChatSearchSnapshot(
            documents: snapshot.data().map { [FirebaseChatSearchDocument(id: snapshot.documentID, data: $0)] } ?? [],
            isFromCache: snapshot.metadata.isFromCache,
            hasPendingWrites: snapshot.metadata.hasPendingWrites
        )
    }

    func candidatesFromServer(query request: FirebaseChatSearchQuery) async throws -> FirebaseChatSearchSnapshot {
        var query = db.collection("Rooms").document(request.roomID).collection("Messages")
            .whereField(request.tokenField, arrayContains: request.token)
            .whereField("seq", isLessThanOrEqualTo: request.upperSeq)
            .order(by: "seq", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: request.limit)
        if let cursor = request.after {
            query = query.start(after: [cursor.seq, cursor.documentID])
        }
        let snapshot = try await query.getDocuments(source: .server)
        return FirebaseChatSearchSnapshot(
            documents: snapshot.documents.map { FirebaseChatSearchDocument(id: $0.documentID, data: $0.data()) },
            isFromCache: snapshot.metadata.isFromCache,
            hasPendingWrites: snapshot.metadata.hasPendingWrites
        )
    }
}
