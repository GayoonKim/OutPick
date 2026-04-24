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
    func createBrand(
        name: String,
        isFeatured: Bool,
        websiteURL: String?,
        lookbookArchiveURL: String?
    ) async throws -> String {
        try await CloudFunctionsManager.shared.createBrand(
            name: name,
            isFeatured: isFeatured,
            websiteURL: websiteURL,
            lookbookArchiveURL: lookbookArchiveURL
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
}
