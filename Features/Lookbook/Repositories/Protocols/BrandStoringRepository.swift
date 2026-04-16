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
    /// 브랜드를 생성하고 생성된 문서 ID를 반환합니다.
    func createBrand(
        name: String,
        isFeatured: Bool
    ) async throws -> String

    /// 생성 후 업로드된 로고 경로를 패치합니다.
    func updateLogoPaths(
        docID: String,
        logoThumbPath: String?,
        logoDetailPath: String?
    ) async throws
}
