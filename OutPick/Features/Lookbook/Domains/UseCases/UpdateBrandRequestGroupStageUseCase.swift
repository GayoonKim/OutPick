//
//  UpdateBrandRequestGroupStageUseCase.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol UpdateBrandRequestGroupStageUseCaseProtocol {
    func execute(
        groupID: String,
        adminStage: BrandRequestAdminStage,
        rejectionReason: BrandRequestRejectionReason?,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt
}

struct UpdateBrandRequestGroupStageUseCase: UpdateBrandRequestGroupStageUseCaseProtocol {
    private let repository: BrandRequestRepositoryProtocol

    init(repository: BrandRequestRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        groupID: String,
        adminStage: BrandRequestAdminStage,
        rejectionReason: BrandRequestRejectionReason?,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        try await repository.updateBrandRequestGroupStage(
            groupID: groupID,
            adminStage: adminStage,
            rejectionReason: rejectionReason,
            adminNote: adminNote
        )
    }
}
