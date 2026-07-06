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
        englishName: String?,
        isFeatured: Bool,
        websiteURL: String?,
        lookbookArchiveURL: String?
    ) async throws -> String

    /// 브랜드 기본 정보를 수정하고 최신 브랜드 값을 반환합니다.
    func updateBrand(
        brandID: BrandID,
        name: String,
        englishName: String?,
        websiteURL: String?,
        lookbookArchiveURL: String?,
        isFeatured: Bool?
    ) async throws -> Brand

    /// 생성 후 업로드된 로고 경로를 패치합니다.
    func updateLogoPaths(
        docID: String,
        logoThumbPath: String?,
        logoDetailPath: String?
    ) async throws

    func addBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt

    func removeBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt
}
