import Foundation

protocol StyleMoodRepositoryProtocol {
    func fetchOnboardingMoods() async throws -> [StyleMood]
}
