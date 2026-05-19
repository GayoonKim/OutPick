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
        return try dto.toDomain()
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

            let dtos: [TagDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
            results.append(contentsOf: try dtos.map { try $0.toDomain() })
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

        let dtos: [TagDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
        return try dtos.map { try $0.toDomain() }
    }
}
