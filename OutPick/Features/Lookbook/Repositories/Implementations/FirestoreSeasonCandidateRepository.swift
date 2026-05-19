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
        let snapshot = try await db
            .collection("brands")
            .document(brandID.value)
            .collection("seasonCandidates")
            .order(by: "sortIndex")
            .getDocuments()

        let dtos: [SeasonCandidateDTO] = try snapshot.documents.map {
            try FirestoreMapper.mapDocument($0)
        }

        return try dtos
            .map { try $0.toDomain() }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }
                return lhs.title < rhs.title
            }
    }
}
