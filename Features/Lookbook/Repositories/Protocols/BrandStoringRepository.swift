//
//  BrandStoring.swift
//  OutPick
//
//  Created by 김가윤 on 1/13/26.
//

import Foundation

/// 브랜드 문서를 저장하는 저장소 추상화입니다.
/// - Note: ViewModel이 Firestore/Cloud Functions 세부 구현을 모르도록 분리합니다.
protocol BrandStoringRepository {
    /// 임시 ID가 필요한 테스트/레거시 경로를 위한 ID 발급 함수입니다.
    /// - Note: 운영 브랜드 생성은 사전에 허용된 brandID를 사용합니다.
    func makeNewBrandDocumentID() -> String

    /// 브랜드를 생성합니다. (권한 검증/저장 세부 구현은 구현체가 책임집니다.)
    func upsertBrand(
        docID: String,
        name: String,
        logoThumbPath: String?,
        logoDetailPath: String?,
        isFeatured: Bool
    ) async throws

    /// 생성 후 비동기 업로드된 디테일 경로만 패치합니다.
    func updateLogoDetailPath(
        docID: String,
        logoDetailPath: String
    ) async throws
}
