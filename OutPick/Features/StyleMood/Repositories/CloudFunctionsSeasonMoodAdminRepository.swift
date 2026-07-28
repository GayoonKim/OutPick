import Foundation

struct CloudFunctionsSeasonMoodAdminRepository: SeasonMoodAdminRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func updateSeasonMoods(
        brandID: BrandID,
        seasonID: SeasonID,
        moodIDs: [String]
    ) async throws {
        _ = try await transport.call(
            "updateSeasonMoods",
            data: [
                "brandID": brandID.value,
                "seasonID": seasonID.value,
                "moodIDs": moodIDs
            ]
        )
    }
}
