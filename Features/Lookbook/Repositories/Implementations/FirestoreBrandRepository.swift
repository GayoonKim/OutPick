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

    func fetchBrand(brandID: BrandID) async throws -> Brand {
        let snapshot = try await db
            .collection("brands")
            .document(brandID.value)
            .getDocument()

        guard snapshot.exists else {
            throw NSError(
                domain: "FirestoreBrandRepository",
                code: -40,
                userInfo: [NSLocalizedDescriptionKey: "브랜드 문서를 찾지 못했습니다."]
            )
        }

        let dto: BrandDTO = try FirestoreMapper.mapDocument(snapshot)
        return try dto.toDomain()
    }

    /// 전체 브랜드 목록 페이지 조회
    func fetchBrands(
        sort: BrandSort? = nil,
        limit: Int,
        after last: DocumentSnapshot? = nil
    ) async throws -> BrandPage {

        var q: Query = db.collection("brands")
        q = applyOrdering(to: q, sort: sort)

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
        sort: BrandSort? = nil,
        limit: Int,
        after last: DocumentSnapshot? = nil
    ) async throws -> BrandPage {

        var q: Query = db.collection("brands")
            .whereField("isFeatured", isEqualTo: true)
        q = applyOrdering(to: q, sort: sort)

        q = q.limit(to: limit)

        if let last {
            q = q.start(afterDocument: last)
        }

        let snap = try await q.getDocuments()
        let dtos: [BrandDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
        let items = try dtos.map { try $0.toDomain() }

        return BrandPage(items: items, last: snap.documents.last)
    }

    private func applyOrdering(to query: Query, sort: BrandSort?) -> Query {
        var q = query

        // 기본: 정렬 미지정 시 Firestore 기본 순서(__name__ 오름차순)를 사용합니다.
        // __name__ 내림차순 명시는 별도 인덱스를 요구할 수 있어 피합니다.
        guard let sort else {
            return q
        }

        // 정렬이 필요한 경우에만 추가 정렬 규칙을 적용합니다.
        q = q.order(by: sort.primaryField, descending: true)
        if sort.primaryField != "updatedAt" {
            q = q.order(by: "updatedAt", descending: true)
        }
        q = q.order(by: FieldPath.documentID())
        return q
    }
}
