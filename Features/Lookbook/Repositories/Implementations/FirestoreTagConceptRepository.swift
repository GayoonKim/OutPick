//
//  FirestoreTagConceptRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation
import FirebaseFirestore

final class FirestoreTagConceptRepository: TagConceptRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchConcept(conceptID: String) async throws -> TagConcept {
        let doc = try await db
            .collection("tagConcepts")
            .document(conceptID)
            .getDocument()

        let dto: TagConceptDTO = try FirestoreMapper.mapDocument(doc)
        return try dto.toDomain()
    }

    /// whereIn 10개 제한 대응
    func fetchConcepts(conceptIDs: [String]) async throws -> [TagConcept] {
        guard !conceptIDs.isEmpty else { return [] }

        let chunks = conceptIDs.chunked(max: 10)
        var results: [TagConcept] = []
        results.reserveCapacity(conceptIDs.count)

        for ids in chunks {
            let snap = try await db
                .collection("tagConcepts")
                .whereField(FieldPath.documentID(), in: ids)
                .getDocuments()

            let dtos: [TagConceptDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
            results.append(contentsOf: try dtos.map { try $0.toDomain() })
        }

        // 요청 순서 보존
        let dict = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        return conceptIDs.compactMap { dict[$0] }
    }
}
