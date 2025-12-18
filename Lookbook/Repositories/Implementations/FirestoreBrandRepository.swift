//
//  FirestoreBrandRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

final class FirestoreBrandRepository: BrandRepositoryProtocol {
    private let db: Firestore

    /// 기본은 Firestore 싱글톤 사용, 테스트/교체를 위해 주입 가능
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    /// 전체 브랜드 목록 조회
    func fetchBrands() async throws -> [Brand] {
        let snap = try await db
            .collection("brands")
            .order(by: "updatedAt", descending: true)
            .getDocuments()

        let dtos: [BrandDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
        return try dtos.map { try $0.toDomain() }
    }

    /// 피처드 브랜드만 조회(홈 상단 노출 등)
    func fetchFeaturedBrands(limit: Int) async throws -> [Brand] {
        let snap = try await db
            .collection("brands")
            .whereField("isFeatured", isEqualTo: true)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        let dtos: [BrandDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
        return try dtos.map { try $0.toDomain() }
    }

    /// 단일 브랜드 조회
    func fetchBrand(brandID: BrandID) async throws -> Brand {
        let doc = try await db
            .collection("brands")
            .document(brandID.value)
            .getDocument()

        let dto: BrandDTO = try FirestoreMapper.mapDocument(doc)
        return try dto.toDomain()
    }
}
