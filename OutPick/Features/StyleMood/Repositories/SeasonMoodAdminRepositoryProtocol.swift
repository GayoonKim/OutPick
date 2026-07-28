import Foundation

protocol SeasonMoodAdminRepositoryProtocol {
    func updateSeasonMoods(
        brandID: BrandID,
        seasonID: SeasonID,
        moodIDs: [String]
    ) async throws
}
