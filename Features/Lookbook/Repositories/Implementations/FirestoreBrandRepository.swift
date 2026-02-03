//
//  FirestoreBrandRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

/// Firestore DocumentSnapshot 기반 페이지네이션 응답
/// - Note: Domain 추상화를 더 강하게 가져가고 싶다면(PageCursor token 방식)로 다시 바꿀 수 있지만,
///         현재는 구현 단순성과 효율을 우선해 Firestore 커서를 그대로 사용합니다.
struct BrandPage {
    let items: [Brand]
    let last: DocumentSnapshot?
}

final class FirestoreBrandRepository: BrandRepositoryProtocol {
    private let db: Firestore

    /// 기본은 Firestore 싱글톤 사용, 테스트/교체를 위해 주입 가능
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    /// 전체 브랜드 목록 페이지 조회
    func fetchBrands(
        sort: BrandSort = .latest,
        limit: Int,
        after last: DocumentSnapshot? = nil
    ) async throws -> BrandPage {

        var q: Query = db.collection("brands")

        // 1차 정렬
        q = q.order(by: sort.primaryField, descending: true)

        // 2차 정렬(동점 처리용) - 최신순일 때는 중복 orderBy를 피함
        if sort.primaryField != "updatedAt" {
            q = q.order(by: "updatedAt", descending: true)
        }

        // 3차 정렬(documentID로 완전 결정) - 페이지 경계 중복/누락 방지
        q = q.order(by: FieldPath.documentID(), descending: true)

        q = q.limit(to: limit)

        if let last {
            q = q.start(afterDocument: last)
        }

        let snap = try await q.getDocuments()
        let dtos: [BrandDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
        let items = try dtos.map { try $0.toDomain() }

        return BrandPage(items: items, last: snap.documents.last)
    }

    /// 피처드 브랜드 목록 페이지 조회
    func fetchFeaturedBrands(
        sort: BrandSort = .latest,
        limit: Int,
        after last: DocumentSnapshot? = nil
    ) async throws -> BrandPage {

        var q: Query = db.collection("brands")
            .whereField("isFeatured", isEqualTo: true)

        // 1차 정렬
        q = q.order(by: sort.primaryField, descending: true)

        // 2차 정렬(동점 처리용) - 최신순일 때는 중복 orderBy를 피함
        if sort.primaryField != "updatedAt" {
            q = q.order(by: "updatedAt", descending: true)
        }

        // 3차 정렬(documentID로 완전 결정) - 페이지 경계 중복/누락 방지
        q = q.order(by: FieldPath.documentID(), descending: true)

        q = q.limit(to: limit)

        if let last {
            q = q.start(afterDocument: last)
        }

        let snap = try await q.getDocuments()
        let dtos: [BrandDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
        let items = try dtos.map { try $0.toDomain() }

        return BrandPage(items: items, last: snap.documents.last)
    }
}
