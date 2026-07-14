//
//  FirestoreReplacementRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

final class FirestoreReplacementRepository: ReplacementRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchReplacements(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        page: PageRequest
    ) async throws -> PageResponse<ReplacementItem> {

        let collectionRef = db
            .collection("brands")
            .document(brandID.value)
            .collection("seasons")
            .document(seasonID.value)
            .collection("posts")
            .document(postID.value)
            .collection("replacements")

        var query: Query = collectionRef
            .order(by: "createdAt", descending: true)
            .limit(to: page.size)

        if let cursor = page.cursor {
            let cursorDoc = try await collectionRef.document(cursor.token).getDocument()
            query = query.start(afterDocument: cursorDoc)
        }

        let snap = try await query.getDocuments()
        let items = try snap.documents.map { document in
            let dto: ReplacementItemDTO = try FirestoreMapper.mapDocument(document)
            return try dto.toDomain(
                documentID: document.documentID,
                postID: postID
            )
        }

        let nextCursor: PageCursor? = (snap.documents.count == page.size)
            ? snap.documents.last.map { PageCursor(token: $0.documentID) }
            : nil

        return PageResponse(items: items, nextCursor: nextCursor)
    }
}
