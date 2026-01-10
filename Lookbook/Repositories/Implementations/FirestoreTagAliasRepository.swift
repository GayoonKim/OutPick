//
//  FirestoreTagAliasRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation
import FirebaseFirestore

final class FirestoreTagAliasRepository: TagAliasRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    /// 검색어 입력 → tagAliases 먼저 조회해서 concept 추천
    /// - Note: raw로 먼저 검색, 부족하면 displayName으로 보완
    func searchAliases(prefix: String, limit: Int) async throws -> [TagAlias] {
        let q = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let end = q + "\u{f8ff}"

        // 1) raw 기준 prefix 검색
        let rawSnap = try await db
            .collection("tagAliases")
            .order(by: "raw")
            .start(at: [q])
            .end(at: [end])
            .limit(to: limit)
            .getDocuments()

        var results: [TagAlias] = try rawSnap.documents.map { doc in
            let dto: TagAliasDTO = try FirestoreMapper.mapDocument(doc)
            return try dto.toDomain()
        }

        // 2) displayName 기준 보완
        if results.count < limit {
            let displaySnap = try await db
                .collection("tagAliases")
                .order(by: "displayName")
                .start(at: [q])
                .end(at: [end])
                .limit(to: limit)
                .getDocuments()

            let more: [TagAlias] = try displaySnap.documents.map { doc in
                let dto: TagAliasDTO = try FirestoreMapper.mapDocument(doc)
                return try dto.toDomain()
            }

            // 중복 제거(문서ID 기준)
            var dict = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
            for a in more { dict[a.id] = a }
            results = Array(dict.values)
        }

        return Array(results.prefix(limit))
    }
}
