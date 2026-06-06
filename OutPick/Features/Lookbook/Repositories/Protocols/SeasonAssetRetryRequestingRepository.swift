import Foundation

protocol SeasonAssetRetryRequestingRepository {
    func requestAssetRetry(
        brandID: BrandID,
        sourceJobID: String
    ) async throws -> SeasonAssetRetryReceipt
}
