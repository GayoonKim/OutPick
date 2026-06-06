import Foundation

struct CloudFunctionsSeasonAssetRetryRepository: SeasonAssetRetryRequestingRepository {
    func requestAssetRetry(
        brandID: BrandID,
        sourceJobID: String
    ) async throws -> SeasonAssetRetryReceipt {
        try await CloudFunctionsManager.shared.requestSeasonAssetRetry(
            brandID: brandID.value,
            sourceJobID: sourceJobID
        )
    }
}
