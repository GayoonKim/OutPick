import Foundation

struct UpdateStylePreferencesUseCase {
    private let mutationRepository: ProfileMutationRepositoryProtocol

    init(mutationRepository: ProfileMutationRepositoryProtocol) {
        self.mutationRepository = mutationRepository
    }

    func execute(selectedMoodIDs: [String]) async throws {
        try await mutationRepository.updateStylePreferences(
            selectedMoodIDs: selectedMoodIDs
        )
    }
}
