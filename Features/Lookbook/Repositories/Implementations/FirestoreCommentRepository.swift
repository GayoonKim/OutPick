//
//  FirestoreCommentRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

final class FirestoreCommentRepository: CommentRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchRepresentativeComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> Comment? {
        let collectionRef = commentsCollection(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID
        )

        // 대표 댓글은 운영자가 고정한 댓글과 분리해서 가장 반응이 높은 루트 댓글만 후보로 봅니다.
        let popularQuery = collectionRef
            .whereField("parentCommentID", isEqualTo: NSNull())
            .order(by: "likeCount", descending: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
        let popularComments = try await fetchVisibleComments(
            query: popularQuery,
            postID: postID
        )
        return popularComments.first(where: { $0.isPinned == false })
    }

    func fetchPinnedRootComments(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        limit: Int
    ) async throws -> [Comment] {
        let query = commentsCollection(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID
        )
        .whereField("parentCommentID", isEqualTo: NSNull())
        .whereField("isPinned", isEqualTo: true)
        .order(by: "pinnedAt", descending: true)
        .limit(to: max(1, limit))

        return try await fetchVisibleComments(query: query, postID: postID)
    }

    func fetchRootComments(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        sort: CommentSortOption,
        page: PageRequest
    ) async throws -> PageResponse<Comment> {
        let collectionRef = commentsCollection(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID
        )
        let sortedQuery = rootCommentsQuery(
            collectionRef: collectionRef,
            sort: sort
        )
        let query = try await applyPage(
            sortedQuery,
            collectionRef: collectionRef,
            page: page
        )

        return try await fetchCommentPage(
            query: query,
            postID: postID,
            pageSize: page.size
        )
    }

    func fetchReplies(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        page: PageRequest
    ) async throws -> PageResponse<Comment> {
        let collectionRef = commentsCollection(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID
        )
        let sortedQuery = collectionRef
            .whereField("parentCommentID", isEqualTo: parentCommentID.value)
            .order(by: "createdAt", descending: false)
        let query = try await applyPage(
            sortedQuery,
            collectionRef: collectionRef,
            page: page
        )

        return try await fetchCommentPage(
            query: query,
            postID: postID,
            pageSize: page.size
        )
    }

    private func commentsCollection(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) -> CollectionReference {
        db
            .collection("brands")
            .document(brandID.value)
            .collection("seasons")
            .document(seasonID.value)
            .collection("posts")
            .document(postID.value)
            .collection("comments")
    }

    private func rootCommentsQuery(
        collectionRef: CollectionReference,
        sort: CommentSortOption
    ) -> Query {
        switch sort {
        case .latest:
            return collectionRef
                .whereField("parentCommentID", isEqualTo: NSNull())
                .order(by: "createdAt", descending: true)
        case .popular:
            return collectionRef
                .whereField("parentCommentID", isEqualTo: NSNull())
                .order(by: "likeCount", descending: true)
                .order(by: "createdAt", descending: true)
        }
    }

    private func applyPage(
        _ query: Query,
        collectionRef: CollectionReference,
        page: PageRequest
    ) async throws -> Query {
        var query = query.limit(to: max(1, page.size))

        if let cursor = page.cursor {
            let cursorDoc = try await collectionRef.document(cursor.token).getDocument()
            query = query.start(afterDocument: cursorDoc)
        }

        return query
    }

    private func fetchCommentPage(
        query: Query,
        postID: PostID,
        pageSize: Int
    ) async throws -> PageResponse<Comment> {
        let snap = try await query.getDocuments()
        let items = try mapVisibleComments(snap.documents, postID: postID)

        let nextCursor: PageCursor? = (snap.documents.count == max(1, pageSize))
            ? snap.documents.last.map { PageCursor(token: $0.documentID) }
            : nil

        return PageResponse(items: items, nextCursor: nextCursor)
    }

    private func fetchVisibleComments(
        query: Query,
        postID: PostID
    ) async throws -> [Comment] {
        let snap = try await query.getDocuments()
        return try mapVisibleComments(snap.documents, postID: postID)
    }

    private func mapVisibleComments(
        _ documents: [QueryDocumentSnapshot],
        postID: PostID
    ) throws -> [Comment] {
        try documents
            .map { document in
                let dto: CommentDTO = try FirestoreMapper.mapDocument(document)
                return try dto.toDomain(postID: postID)
            }
            .filter { $0.isDeleted == false }
    }
}
