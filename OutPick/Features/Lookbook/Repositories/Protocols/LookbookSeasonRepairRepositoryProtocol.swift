import Foundation

protocol LookbookSeasonRepairRepositoryProtocol {
    func requestRepair(
        brandID: BrandID,
        seasonID: SeasonID,
        sourceImportJobID: String
    ) async throws -> LookbookSeasonRepairReceipt

    func loadPreview(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookSeasonRepairPreview

    func applyRepair(
        brandID: BrandID,
        preview: LookbookSeasonRepairPreview
    ) async throws -> LookbookSeasonRepairReceipt
}
