//
//  FirestorePostRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

final class FirestorePostRepository: PostRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchPosts(
        brandID: BrandID,
        seasonID: SeasonID,
        sort: PostSortOption,
        filterTagIDs: [TagID],
        page: PageRequest
    ) async throws -> PageResponse<LookbookPost> {

        let collectionRef = db
            .collection("brands")
            .document(brandID.value)
            .collection("seasons")
            .document(seasonID.value)
            .collection("posts")

        var query: Query = collectionRef

        /// 태그 필터
        if filterTagIDs.count == 1 {
            query = query.whereField("tagIDs", arrayContains: filterTagIDs[0].value)
        } else if filterTagIDs.count > 1 {
            /// arrayContainsAny는 최대 10개 제한
            query = query.whereField("tagIDs", arrayContainsAny: Array(filterTagIDs.prefix(10)).map(\.value))
        }

        /// 정렬
        query = applySort(query, sort: sort)

        /// 페이지 사이즈
        query = query.limit(to: page.size)

        /// 커서(토큰 = 마지막 문서ID)
        if let cursor = page.cursor {
            let cursorDoc = try await collectionRef.document(cursor.token).getDocument()
            query = query.start(afterDocument: cursorDoc)
        }

        let snap = try await query.getDocuments()
        let dtos: [PostDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
        let items = try dtos.map { try $0.toDomain(brandID: brandID, seasonID: seasonID) }

        let nextCursor: PageCursor? = (snap.documents.count == page.size)
            ? snap.documents.last.map { PageCursor(token: $0.documentID) }
            : nil

        return PageResponse(items: items, nextCursor: nextCursor)
    }

    func fetchPost(brandID: BrandID, seasonID: SeasonID, postID: PostID) async throws -> LookbookPost {
        let doc = try await db
            .collection("brands")
            .document(brandID.value)
            .collection("seasons")
            .document(seasonID.value)
            .collection("posts")
            .document(postID.value)
            .getDocument()

        let dto: PostDTO = try FirestoreMapper.mapDocument(doc)
        return try dto.toDomain(brandID: brandID, seasonID: seasonID)
    }

    func fetchPostsByTag(tagID: TagID, sort: PostSortOption, page: PageRequest) async throws -> PageResponse<LookbookPost> {
        var query: Query = db
            .collectionGroup("posts")
            .whereField("tagIDs", arrayContains: tagID.value)

        query = applySort(query, sort: sort)
        query = query.limit(to: page.size)

        /// collectionGroup 커서는 “토큰에 문서 fullPath 저장” 전략이 가장 안전함
        if let cursor = page.cursor {
            let cursorDoc = try await db.document(cursor.token).getDocument() // token=fullPath 전제
            query = query.start(afterDocument: cursorDoc)
        }

        let snap = try await query.getDocuments()
        let dtos: [PostDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }

        /// 전역 조회에서는 경로 주입이 어려우니 문서 필드에 brandID/seasonID가 들어있다는 전제의 변환 사용
        let items = try dtos.map { try $0.toDomainFromEmbeddedPathIDs() }

        let nextCursor: PageCursor? = (snap.documents.count == page.size)
            ? snap.documents.last.map { PageCursor(token: $0.reference.path) } // 다음 커서도 fullPath로 저장
            : nil

        return PageResponse(items: items, nextCursor: nextCursor)
    }

    private func applySort(_ query: Query, sort: PostSortOption) -> Query {
        switch sort {
        case .newest:
            return query.order(by: "createdAt", descending: true)
        case .mostCommented:
            return query.order(by: "metrics.commentCount", descending: true)
        case .mostReplaced:
            return query.order(by: "metrics.replacementCount", descending: true)
        case .mostSaved:
            return query.order(by: "metrics.saveCount", descending: true)
        case .trending:
            /// 잘 모르겠습니다: trending 정렬 필드는 프로젝트 스키마에 따라 달라집니다.
            /// 추측입니다: viewCount 기반을 임시로 사용합니다.
            return query.order(by: "metrics.viewCount", descending: true)
        }
    }
}
