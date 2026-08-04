import Foundation

@MainActor
final class SeasonDiscoveryReviewViewModel: ObservableObject {
    @Published private(set) var candidates: [SeasonDiscoveryReviewCandidate] = []
    @Published private(set) var seasons: [Season] = []
    @Published private(set) var isLoading = false
    @Published private(set) var resolvingCandidateID: String?
    @Published private(set) var errorMessage: String?

    let job: SeasonCandidateDiscoveryResult

    private let repository: any SeasonCandidateDiscoveryRepositoryProtocol
    private let seasonRepository: any SeasonRepositoryProtocol
    private let onCompleted: () -> Void

    init(
        job: SeasonCandidateDiscoveryResult,
        repository: any SeasonCandidateDiscoveryRepositoryProtocol,
        seasonRepository: any SeasonRepositoryProtocol,
        onCompleted: @escaping () -> Void
    ) {
        self.job = job
        self.repository = repository
        self.seasonRepository = seasonRepository
        self.onCompleted = onCompleted
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedCandidates = repository.fetchReviewCandidates(
                brandID: job.brandID,
                jobID: job.jobID
            )
            async let loadedSeasons = seasonRepository.fetchAllSeasons(
                brandID: job.brandID
            )
            let values = try await (loadedCandidates, loadedSeasons)
            candidates = values.0
            seasons = values.1.sorted(by: Season.defaultSort)
            if candidates.isEmpty {
                onCompleted()
            }
        } catch {
            errorMessage = "검토할 시즌 후보를 불러오지 못했습니다."
        }
    }

    func keepAsNew(_ candidate: SeasonDiscoveryReviewCandidate) async {
        await resolve(candidate, decision: "keepAsNew", targetSeasonID: nil)
    }

    func reject(_ candidate: SeasonDiscoveryReviewCandidate) async {
        await resolve(candidate, decision: "reject", targetSeasonID: nil)
    }

    func connect(
        _ candidate: SeasonDiscoveryReviewCandidate,
        to season: Season
    ) async {
        await resolve(
            candidate,
            decision: "connectExistingSeason",
            targetSeasonID: season.id
        )
    }

    func clearError() {
        errorMessage = nil
    }

    private func resolve(
        _ candidate: SeasonDiscoveryReviewCandidate,
        decision: String,
        targetSeasonID: SeasonID?
    ) async {
        guard resolvingCandidateID == nil else { return }
        resolvingCandidateID = candidate.id
        errorMessage = nil
        defer { resolvingCandidateID = nil }

        do {
            try await repository.resolveReviewCandidate(
                brandID: job.brandID,
                job: job,
                candidateID: candidate.id,
                decision: decision,
                targetSeasonID: targetSeasonID
            )
            candidates.removeAll { $0.id == candidate.id }
            if candidates.isEmpty {
                onCompleted()
            }
        } catch {
            errorMessage = "후보 결정을 저장하지 못했습니다. 최신 결과를 다시 확인해주세요."
        }
    }
}
