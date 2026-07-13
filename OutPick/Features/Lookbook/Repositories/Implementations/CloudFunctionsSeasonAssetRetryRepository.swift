import Foundation

struct CloudFunctionsSeasonAssetRetryRepository: SeasonAssetRetryRequestingRepository {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func requestAssetRetry(
        brandID: BrandID,
        sourceJobID: String
    ) async throws -> SeasonAssetRetryReceipt {
        let response = try await transport.call(
            "requestSeasonAssetRetry",
            data: [
                "brandID": brandID.value,
                "sourceJobID": sourceJobID
            ]
        )
        return try SeasonImportCloudFunctionsMapper.assetRetryReceipt(response)
    }
}
