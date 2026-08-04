//
//  FirestoreSeasonCandidateRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation
import FirebaseFirestore

final class FirestoreSeasonCandidateRepository: SeasonCandidateRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchSeasonCandidates(
        brandID: BrandID
    ) async throws -> [SeasonCandidate] {
        let brandRef = db.collection("brands").document(brandID.value)
        let brandSnapshot = try await brandRef.getDocument()
        guard let discoveryJobID = brandSnapshot.data()?["publishedSeasonDiscoveryJobID"] as? String,
              discoveryJobID.isEmpty == false else {
            return []
        }
        if let expiresAt = brandSnapshot.data()?["publishedSeasonDiscoveryExpiresAt"] as? Timestamp,
           expiresAt.dateValue() <= Date() {
            return []
        }
        let snapshot = try await brandRef
            .collection("seasonDiscoveryJobs")
            .document(discoveryJobID)
            .collection("candidates")
            .whereField("resolution", isEqualTo: "newSeason")
            .order(by: "sortIndex")
            .getDocuments()

        return try snapshot.documents
            .map { document in
                let dto: SeasonCandidateDTO = try FirestoreMapper.mapDocument(document)
                return try dto.toDomain(documentID: document.documentID)
            }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }
                return lhs.title < rhs.title
            }
    }
}
