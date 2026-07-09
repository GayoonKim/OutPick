//
//  ListBrandRequestGroupsUseCase.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol ListBrandRequestGroupsUseCaseProtocol {
    func execute(
        adminStage: BrandRequestAdminStage?,
        processedScope: ProcessedRequestScope?,
        limit: Int,
        cursor: AdminBrandRequestGroupPage.Cursor?
    ) async throws -> AdminBrandRequestGroupPage
}

struct ListBrandRequestGroupsUseCase: ListBrandRequestGroupsUseCaseProtocol {
    private let repository: BrandRequestRepositoryProtocol

    init(repository: BrandRequestRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        adminStage: BrandRequestAdminStage?,
        processedScope: ProcessedRequestScope?,
        limit: Int,
        cursor: AdminBrandRequestGroupPage.Cursor?
    ) async throws -> AdminBrandRequestGroupPage {
        try await repository.listBrandRequestGroups(
            adminStage: adminStage,
            processedScope: processedScope,
            limit: limit,
            cursor: cursor
        )
    }
}
