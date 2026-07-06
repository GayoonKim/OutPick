//
//  ListMyBrandRequestsUseCase.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol ListMyBrandRequestsUseCaseProtocol {
    func execute(
        scope: BrandRequestListScope,
        limit: Int,
        cursor: BrandRequestPage.Cursor?
    ) async throws -> BrandRequestPage
}

struct ListMyBrandRequestsUseCase: ListMyBrandRequestsUseCaseProtocol {
    private let repository: BrandRequestRepositoryProtocol

    init(repository: BrandRequestRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        scope: BrandRequestListScope,
        limit: Int,
        cursor: BrandRequestPage.Cursor?
    ) async throws -> BrandRequestPage {
        try await repository.listMyBrandRequests(
            scope: scope,
            limit: limit,
            cursor: cursor
        )
    }
}
