//
//  SubmitBrandRequestUseCase.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol SubmitBrandRequestUseCaseProtocol {
    func execute(
        brandName: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt
}

struct SubmitBrandRequestUseCase: SubmitBrandRequestUseCaseProtocol {
    private let repository: BrandRequestRepositoryProtocol

    init(repository: BrandRequestRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        brandName: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt {
        try await repository.submitBrandRequest(
            brandName: brandName,
            englishBrandName: englishBrandName
        )
    }
}
