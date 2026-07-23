import Foundation

protocol ManageLookbookSeasonRepairUseCaseProtocol {
    func request(
        brandID: BrandID,
        seasonID: SeasonID,
        sourceImportJobID: String
    ) async throws -> LookbookSeasonRepairReceipt

    func loadPreview(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookSeasonRepairPreview

    func apply(
        brandID: BrandID,
        preview: LookbookSeasonRepairPreview
    ) async throws -> LookbookSeasonRepairReceipt
}

final class ManageLookbookSeasonRepairUseCase:
    ManageLookbookSeasonRepairUseCaseProtocol {
    private let repository: any LookbookSeasonRepairRepositoryProtocol

    init(repository: any LookbookSeasonRepairRepositoryProtocol) {
        self.repository = repository
    }

    func request(
        brandID: BrandID,
        seasonID: SeasonID,
        sourceImportJobID: String
    ) async throws -> LookbookSeasonRepairReceipt {
        try await repository.requestRepair(
            brandID: brandID,
            seasonID: seasonID,
            sourceImportJobID: sourceImportJobID
        )
    }

    func loadPreview(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookSeasonRepairPreview {
        try await repository.loadPreview(brandID: brandID, jobID: jobID)
    }

    func apply(
        brandID: BrandID,
        preview: LookbookSeasonRepairPreview
    ) async throws -> LookbookSeasonRepairReceipt {
        try await repository.applyRepair(brandID: brandID, preview: preview)
    }
}
