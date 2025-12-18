//
//  BrandRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

/// Brand 데이터 접근을 추상화하는 Repository 프로토콜
/// - Note: 현재는 구현 단순성과 효율을 우선해 Firestore의 `DocumentSnapshot`을 커서로 그대로 노출합니다.
///         나중에 데이터 소스를 교체하거나 Domain 추상화를 강화하고 싶다면(PageCursor token 방식 등)로 변경할 수 있습니다.
protocol BrandRepositoryProtocol {
    func fetchBrands(
        sort: BrandSort,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage

    func fetchFeaturedBrands(
        sort: BrandSort,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage
}
