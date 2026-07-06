//
//  BrandSearchRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol BrandSearchRepositoryProtocol {
    func searchBrands(query: String, limit: Int) async throws -> [Brand]
}
