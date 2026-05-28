//
//  FirestoreSeasonUserStateRepository.swift
//  OutPick
//
//  Created by Codex on 5/27/26.
//

import Foundation
import FirebaseFirestore

final class FirestoreSeasonUserStateRepository: SeasonUserStateRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchSeasonUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> SeasonUserState? {
        let doc = try await db
            .collection("users")
            .document(userID.value)
            .collection("seasonStates")
            .document(Self.seasonStateDocumentID(
                brandID: brandID,
                seasonID: seasonID
            ))
            .getDocument()

        guard doc.exists else { return nil }

        let dto: SeasonUserStateDTO = try FirestoreMapper.mapDocument(doc)
        return dto.toDomain(
            brandID: brandID,
            seasonID: seasonID,
            userID: userID
        )
    }

    func fetchLikedSeasonUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonUserStatePage {
        var query: Query = db
            .collection("users")
            .document(userID.value)
            .collection("seasonStates")
            .order(by: "likedAt", descending: true)
            .limit(to: limit)

        if let last {
            query = query.start(afterDocument: last)
        }

        let snap = try await query.getDocuments()
        let items = try snap.documents.map { document in
            let dto: SeasonUserStateDTO = try FirestoreMapper.mapDocument(document)
            let stateIDs = Self.parseSeasonStateDocumentID(document.documentID)
            let brandID = BrandID(value: dto.brandID ?? stateIDs.brandID)
            let seasonID = SeasonID(value: dto.seasonID ?? stateIDs.seasonID)
            return dto.toDomain(
                brandID: brandID,
                seasonID: seasonID,
                userID: userID
            )
        }

        return SeasonUserStatePage(items: items, last: snap.documents.last)
    }

    private static func seasonStateDocumentID(
        brandID: BrandID,
        seasonID: SeasonID
    ) -> String {
        "\(brandID.value)_\(seasonID.value)"
    }

    private static func parseSeasonStateDocumentID(_ documentID: String) -> (brandID: String, seasonID: String) {
        let parts = documentID.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return (documentID, "")
        }
        return (parts[0], parts[1])
    }
}
