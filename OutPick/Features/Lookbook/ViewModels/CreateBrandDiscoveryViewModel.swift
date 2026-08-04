//
//  CreateBrandDiscoveryViewModel.swift
//  OutPick
//

import Foundation

@MainActor
final class CreateBrandDiscoveryViewModel: ObservableObject {
    @Published private(set) var result: SeasonCandidateDiscoveryResult?
    @Published private(set) var errorMessage: String?

    private let repository: any SeasonCandidateDiscoveryRepositoryProtocol
    private var observationTask: Task<Void, Never>?

    init(repository: any SeasonCandidateDiscoveryRepositoryProtocol) {
        self.repository = repository
    }

    func start(brandID: BrandID, existingJobID: String? = nil) {
        observationTask?.cancel()
        result = nil
        errorMessage = nil
        observationTask = Task {
            do {
                if let existingJobID {
                    result = try await repository.observeSeasonDiscovery(
                        brandID: brandID,
                        jobID: existingJobID
                    )
                } else {
                    result = try await repository.discoverSeasonCandidates(brandID: brandID)
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }
}
