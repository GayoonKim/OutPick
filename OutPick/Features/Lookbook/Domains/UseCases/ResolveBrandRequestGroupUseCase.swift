//
//  ResolveBrandRequestGroupUseCase.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol ResolveBrandRequestGroupUseCaseProtocol {
    func execute(
        groupID: String,
        resolvedBrandID: BrandID,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt
}

struct ResolveBrandRequestGroupUseCase: ResolveBrandRequestGroupUseCaseProtocol {
    private let repository: BrandRequestRepositoryProtocol

    init(repository: BrandRequestRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        groupID: String,
        resolvedBrandID: BrandID,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        try await repository.resolveBrandRequestGroup(
            groupID: groupID,
            resolvedBrandID: resolvedBrandID,
            adminNote: adminNote
        )
    }
}
