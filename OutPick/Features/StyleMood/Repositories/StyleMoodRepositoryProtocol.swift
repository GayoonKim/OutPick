import Foundation

protocol StyleMoodRepositoryProtocol {
    func fetchOnboardingMoods() async throws -> [StyleMood]
    func fetchAllMoods() async throws -> [StyleMood]
}

extension StyleMoodRepositoryProtocol {
    func fetchAllMoods() async throws -> [StyleMood] {
        try await fetchOnboardingMoods()
    }
}
