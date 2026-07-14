//
//  FirestoreTagRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

final class FirestoreTagRepository: TagRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchTag(tagID: TagID) async throws -> Tag {
        let doc = try await db
            .collection("tags")
            .document(tagID.value)
            .getDocument()

        let dto: TagDTO = try FirestoreMapper.mapDocument(doc)
        return try dto.toDomain(documentID: doc.documentID)
    }

    /// 여러 태그를 한 번에 조회(참고: Firestore whereIn은 10개 제한)
    func fetchTags(tagIDs: [TagID]) async throws -> [Tag] {
        guard !tagIDs.isEmpty else { return [] }

        let chunks = tagIDs.map(\.value).chunked(max: 10)

        var results: [Tag] = []
        results.reserveCapacity(tagIDs.count)

        for ids in chunks {
            let snap = try await db
                .collection("tags")
                .whereField(FieldPath.documentID(), in: ids)
                .getDocuments()

            let tags = try snap.documents.map { document in
                let dto: TagDTO = try FirestoreMapper.mapDocument(document)
                return try dto.toDomain(documentID: document.documentID)
            }
            results.append(contentsOf: tags)
        }

        // 한국어 주석: 요청 순서 보존
        let dict = Dictionary(uniqueKeysWithValues: results.map { ($0.id.value, $0) })
        return tagIDs.compactMap { dict[$0.value] }
    }

    /// /tags prefix 검색 (normalized 기반)
    func searchTags(prefix: String, limit: Int) async throws -> [Tag] {
        let q = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let end = q + "\u{f8ff}"

        let snap = try await db
            .collection("tags")
            .order(by: "normalized")
            .start(at: [q])
            .end(at: [end])
            .limit(to: limit)
            .getDocuments()

        return try snap.documents.map { document in
            let dto: TagDTO = try FirestoreMapper.mapDocument(document)
            return try dto.toDomain(documentID: document.documentID)
        }
    }
}
