//
//  BrandStoring.swift
//  OutPick
//
//  Created by 김가윤 on 1/13/26.
//

import Foundation

/// 브랜드 문서를 저장하는 저장소 추상화입니다.
/// - Note: ViewModel이 Firestore를 모르도록 분리합니다.
protocol BrandStoringRepository {
    /// Firestore 자동 생성 문서 ID를 미리 발급합니다.
    /// - Note: 네트워크를 타지 않고 로컬에서 ID만 생성할 수 있습니다.
    func makeNewBrandDocumentID() -> String

    /// 브랜드를 생성/업데이트합니다. (Firestore 세부 필드 구성은 구현체가 책임집니다.)
    func upsertBrand(
        docID: String,
        name: String,
        logoThumbPath: String?,
        logoOriginalPath: String?,
        isFeatured: Bool
    ) async throws
}
