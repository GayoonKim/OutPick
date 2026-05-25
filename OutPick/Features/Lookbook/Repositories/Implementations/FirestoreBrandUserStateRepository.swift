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
}
