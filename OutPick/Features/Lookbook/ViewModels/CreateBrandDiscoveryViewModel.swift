//
//  CreateBrandDiscoveryViewModel.swift
//  OutPick
//

import Foundation

@MainActor
final class CreateBrandDiscoveryViewModel: ObservableObject {
    static let userFacingLoadFailureMessage =
        "시즌 목록을 불러오지 못했어요. 브랜드 등록을 마친 뒤 다시 찾아올 수 있어요."

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
                let nsError = error as NSError
                print(
                    "[CreateBrandDiscoveryViewModel] 시즌 목록 조회 실패 " +
                    "domain=\(nsError.domain) code=\(nsError.code) " +
                    "description=\(nsError.localizedDescription)"
                )
                errorMessage = Self.userFacingLoadFailureMessage
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }
}
