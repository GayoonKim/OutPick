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

        /// 요청 순서를 보존하고 싶다면 재정렬
        let dict = Dictionary(uniqueKeysWithValues: results.map { ($0.id.value, $0) })
        return tagIDs.compactMap { dict[$0.value] }
    }
}

private extension Array {
    /// 배열을 max 개수 단위로 자르는 유틸 (whereIn 10개 제한 대응)
    func chunked(max: Int) -> [[Element]] {
        guard max > 0 else { return [self] }
        var result: [[Element]] = []
        var i = 0
        while i < count {
            let end = Swift.min(i + max, count)
            result.append(Array(self[i..<end]))
            i = end
        }
        return result
    }
}
