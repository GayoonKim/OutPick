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

        return try snapshot.documents
            .map { document in
                let dto: SeasonImportJobDTO = try FirestoreMapper.mapDocument(document)
                return try dto.toDomain(documentID: document.documentID)
            }
            .filter { $0.jobType == .importSeasonFromURL }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchActiveJobs(
        brandID: BrandID
    ) async throws -> [SeasonImportJob] {
        let activeStatuses = SeasonImportJobStatus.allCases
            .filter { $0.blocksDuplicateImportRequest }
            .map(\.rawValue)

        let snapshot = try await db
            .collection("brands")
            .document(brandID.value)
            .collection("importJobs")
            .whereField("status", in: activeStatuses)
            .limit(to: 300)
            .getDocuments()

        return try snapshot.documents
            .map { document in
                let dto: SeasonImportJobDTO = try FirestoreMapper.mapDocument(document)
                return try dto.toDomain(documentID: document.documentID)
            }
            .filter { $0.jobType == .importSeasonFromURL }
            .filter { $0.status.blocksDuplicateImportRequest }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchJobs(
        brandID: BrandID,
        sourceCandidateIDs: [String]
    ) async throws -> [SeasonImportJob] {
        let uniqueCandidateIDs = Array(Set(sourceCandidateIDs))
        guard uniqueCandidateIDs.isEmpty == false else { return [] }

        var jobs: [SeasonImportJob] = []
        for chunk in uniqueCandidateIDs.chunked(into: 10) {
            let snapshot = try await db
                .collection("brands")
                .document(brandID.value)
                .collection("importJobs")
                .whereField("sourceCandidateID", in: chunk)
                .getDocuments()

            let chunkJobs: [SeasonImportJob] = try snapshot.documents
                .map { document in
                    let dto: SeasonImportJobDTO = try FirestoreMapper.mapDocument(document)
                    return try dto.toDomain(documentID: document.documentID)
                }
                .filter { $0.jobType == .importSeasonFromURL }

            jobs.append(contentsOf: chunkJobs)
        }

        return jobs.sorted { $0.createdAt < $1.createdAt }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }

        var chunks: [[Element]] = []
        var index = startIndex

        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }

        return chunks
    }
}
