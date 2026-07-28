import Foundation

final class CheckNicknameAvailabilityUseCase {
    private let mutationRepository: ProfileMutationRepositoryProtocol

    init(mutationRepository: ProfileMutationRepositoryProtocol) {
        self.mutationRepository = mutationRepository
    }

    func execute(nickname: String) async throws -> Bool {
        try await mutationRepository.checkNicknameAvailability(nickname: nickname)
    }
}
