//
//  FirestoreBrandUserStateRepository.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation
import FirebaseFirestore

final class FirestoreBrandUserStateRepository: BrandUserStateRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchBrandUserState(
        userID: UserID,
        brandID: BrandID
    ) async throws -> BrandUserState? {
        let doc = try await db
            .collection("users")
            .document(userID.value)
            .collection("brandStates")
            .document(brandID.value)
            .getDocument()

        guard doc.exists else { return nil }

        let dto: BrandUserStateDTO = try FirestoreMapper.mapDocument(doc)
        return dto.toDomain(brandID: brandID, userID: userID)
    }

    func fetchLikedBrandUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandUserStatePage {
        var query: Query = db
            .collection("users")
            .document(userID.value)
            .collection("brandStates")
            .order(by: "likedAt", descending: true)
            .limit(to: limit)

        if let last {
            query = query.start(afterDocument: last)
        }

        let snap = try await query.getDocuments()
        let items = try snap.documents.map { document in
            let dto: BrandUserStateDTO = try FirestoreMapper.mapDocument(document)
            let brandID = BrandID(value: dto.brandID ?? document.documentID)
            return dto.toDomain(brandID: brandID, userID: userID)
        }

        return BrandUserStatePage(items: items, last: snap.documents.last)
    }
}
