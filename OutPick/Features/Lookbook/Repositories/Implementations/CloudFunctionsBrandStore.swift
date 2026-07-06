//
//  CloudFunctionsBrandStore.swift
//  OutPick
//
//  Created by Codex on 4/16/26.
//

import Foundation

/// Cloud Functions를 통해 브랜드 문서를 생성/수정하는 BrandStoring 구현입니다.
/// - Note: 브랜드 문서 직접 쓰기는 Firestore Rules에서 차단하고, 서버 권한 검증을 통과한 요청만 반영합니다.
struct CloudFunctionsBrandStore: BrandStoringRepository {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func createBrand(
        name: String,
        isFeatured: Bool,
        websiteURL: String?,
        lookbookArchiveURL: String?
    ) async throws -> String {
        try await cloudFunctionsManager.createBrand(
            name: name,
            isFeatured: isFeatured,
            websiteURL: websiteURL,
            lookbookArchiveURL: lookbookArchiveURL
        )
    }

    func updateBrand(
        brandID: BrandID,
        name: String,
        websiteURL: String?,
        lookbookArchiveURL: String?,
        isFeatured: Bool?
    ) async throws -> Brand {
        try await cloudFunctionsManager.updateBrand(
            brandID: brandID.value,
            name: name,
            websiteURL: websiteURL,
            lookbookArchiveURL: lookbookArchiveURL,
            isFeatured: isFeatured
        )
    }

    func updateLogoPaths(
        docID: String,
        logoThumbPath: String?,
        logoDetailPath: String?
    ) async throws {
        _ = try await CloudFunctionsManager.shared.updateBrandLogoPaths(
            brandID: docID,
            logoThumbPath: logoThumbPath,
            logoDetailPath: logoDetailPath
        )
    }

    func addBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        try await cloudFunctionsManager.addBrandManager(
            brandID: brandID.value,
            email: email,
            role: role
        )
    }

    func removeBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        try await cloudFunctionsManager.removeBrandManager(
            brandID: brandID.value,
            email: email,
            role: role
        )
    }
}
