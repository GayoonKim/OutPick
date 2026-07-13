//
//  CloudFunctionsBrandSearchRepository.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

final class CloudFunctionsBrandSearchRepository: BrandSearchRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func searchBrands(query: String, limit: Int) async throws -> [Brand] {
        let response = try await transport.call(
            "searchBrands",
            data: ["query": query, "limit": limit]
        )
        return try CloudFunctionResponseDecoder(dictionary: response)
            .dictionaries("brands")
            .map(BrandCloudFunctionsMapper.brand)
    }
}
