//
//  CloudFunctionsBrandSearchRepository.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

final class CloudFunctionsBrandSearchRepository: BrandSearchRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func searchBrands(query: String, limit: Int) async throws -> [Brand] {
        try await cloudFunctionsManager.searchBrands(
            query: query,
            limit: limit
        )
    }
}
