//
//  SearchBrandsUseCase.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol SearchBrandsUseCaseProtocol {
    func execute(query: String, limit: Int) async throws -> [Brand]
}

struct SearchBrandsUseCase: SearchBrandsUseCaseProtocol {
    private let repository: BrandSearchRepositoryProtocol

    init(repository: BrandSearchRepositoryProtocol) {
        self.repository = repository
    }

    func execute(query: String, limit: Int) async throws -> [Brand] {
        try await repository.searchBrands(query: query, limit: limit)
    }
}
