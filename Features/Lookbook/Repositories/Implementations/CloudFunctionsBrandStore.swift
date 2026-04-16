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

    func makeNewBrandDocumentID() -> String {
        UUID().uuidString.lowercased()
    }

    func upsertBrand(
        docID: String,
        name: String,
        logoThumbPath: String?,
        logoDetailPath: String?,
        isFeatured: Bool
    ) async throws {
        _ = try await CloudFunctionsManager.shared.createBrand(
            brandID: docID,
            name: name,
            logoThumbPath: logoThumbPath,
            logoDetailPath: logoDetailPath,
            isFeatured: isFeatured
        )
    }

    func updateLogoDetailPath(
        docID: String,
        logoDetailPath: String
    ) async throws {
        _ = try await CloudFunctionsManager.shared.updateBrandLogoDetailPath(
            brandID: docID,
            logoDetailPath: logoDetailPath
        )
    }
}
