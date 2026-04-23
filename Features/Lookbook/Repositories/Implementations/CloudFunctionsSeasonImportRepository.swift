//
//  CloudFunctionsSeasonImportRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

/// Cloud Functions를 통해 시즌 URL import job을 생성하는 구현입니다.
struct CloudFunctionsSeasonImportRepository: SeasonImportRequestingRepository {
    func requestSeasonImport(
        brandID: BrandID,
        seasonURL: String
    ) async throws -> SeasonImportRequestReceipt {
        try await CloudFunctionsManager.shared.requestSeasonImport(
            brandID: brandID.value,
            seasonURL: seasonURL
        )
    }
}
