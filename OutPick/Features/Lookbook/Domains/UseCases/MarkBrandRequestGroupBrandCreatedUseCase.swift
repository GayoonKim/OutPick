//
//  MarkBrandRequestGroupBrandCreatedUseCase.swift
//  OutPick
//
//  Created by Codex on 7/7/26.
//

import Foundation

protocol MarkBrandRequestGroupBrandCreatedUseCaseProtocol {
    func execute(
        groupID: String,
        createdBrandID: BrandID
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt
}

struct MarkBrandRequestGroupBrandCreatedUseCase: MarkBrandRequestGroupBrandCreatedUseCaseProtocol {
    private let repository: BrandRequestRepositoryProtocol

    init(repository: BrandRequestRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        groupID: String,
        createdBrandID: BrandID
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        try await repository.markBrandRequestGroupBrandCreated(
            groupID: groupID,
            createdBrandID: createdBrandID
        )
    }
}
