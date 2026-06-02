//
//  FirestorePostUserStateRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

final class FirestorePostUserStateRepository: PostUserStateRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchPostUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> PostUserState? {
        let doc = try await db
            .collection("users")
            .document(userID.value)
            .collection("postStates")
            .document(Self.postStateDocumentID(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID
            ))
            .getDocument()

        /// 문서가 없으면 nil
        guard doc.exists else { return nil }

        let dto: PostUserStateDTO = try FirestoreMapper.mapDocument(doc)
        /// 경로에서 주입(권장)
        return dto.toDomain(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: userID
        )
    }

    func fetchLikedPostUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> PostUserStatePage {
        var query: Query = db
            .collection("users")
            .document(userID.value)
            .collection("postStates")
            .order(by: "likedAt", descending: true)
            .limit(to: limit)

        if let last {
            query = query.start(afterDocument: last)
        }

        let snap = try await query.getDocuments()
        let items = try snap.documents.map { document in
            let dto: PostUserStateDTO = try FirestoreMapper.mapDocument(document)
            return try dto.toLikedDomain(userID: userID)
        }

        return PostUserStatePage(items: items, last: snap.documents.last)
    }

    private static func postStateDocumentID(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) -> String {
        // 사용자별 좋아요/저장 상태 문서를 시즌 경로까지 포함해 충돌 없이 식별합니다.
        "\(brandID.value)_\(seasonID.value)_\(postID.value)"
    }
}
