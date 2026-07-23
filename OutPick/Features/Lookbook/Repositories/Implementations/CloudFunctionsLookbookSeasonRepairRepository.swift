import Foundation

struct CloudFunctionsLookbookSeasonRepairRepository:
    LookbookSeasonRepairRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func requestRepair(
        brandID: BrandID,
        seasonID: SeasonID,
        sourceImportJobID: String
    ) async throws -> LookbookSeasonRepairReceipt {
        let response = try await transport.call(
            "requestLookbookSeasonRepair",
            data: [
                "brandID": brandID.value,
                "seasonID": seasonID.value,
                "sourceImportJobID": sourceImportJobID
            ]
        )
        return try LookbookSeasonRepairCloudFunctionsMapper.receipt(response)
    }

    func loadPreview(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookSeasonRepairPreview {
        let response = try await transport.call(
            "previewLookbookSeasonRepair",
            data: ["brandID": brandID.value, "jobID": jobID]
        )
        return try LookbookSeasonRepairCloudFunctionsMapper.preview(response)
    }

    func applyRepair(
        brandID: BrandID,
        preview: LookbookSeasonRepairPreview
    ) async throws -> LookbookSeasonRepairReceipt {
        let response = try await transport.call(
            "applyLookbookSeasonRepair",
            data: [
                "brandID": brandID.value,
                "jobID": preview.jobID,
                "repairGeneration": preview.generation,
                "repairSnapshotHash": preview.snapshotHash
            ]
        )
        return try LookbookSeasonRepairCloudFunctionsMapper.receipt(response)
    }
}
