//
//  FirestoreSeasonImportJobRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation
import FirebaseFirestore

final class FirestoreSeasonImportJobRepository: SeasonImportJobRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchLatestJobs(
        brandID: BrandID,
        limit: Int = 10
    ) async throws -> [SeasonImportJob] {
        let snapshot = try await db
            .collection("brands")
            .document(brandID.value)
            .collection("importJobs")
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        let dtos: [SeasonImportJobDTO] = try snapshot.documents.map {
            try FirestoreMapper.mapDocument($0)
        }

        return try dtos
            .map { try $0.toDomain() }
            .filter { $0.jobType == .importSeasonFromURL }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
