import Foundation
import Testing
@testable import OutPick

@MainActor
struct LookbookSeasonRepairViewModelTests {
    @Test func requestsPreviewAndAppliesTheSameSnapshot() async {
        let repository = SeasonRepairRepositoryFake()
        repository.preview = makePreview()
        var completed = false
        let viewModel = makeViewModel(
            repository: repository,
            onCompleted: { completed = true }
        )

        await viewModel.start()
        await viewModel.apply()

        #expect(viewModel.preview?.snapshotHash == "snapshot-1")
        #expect(repository.requestCount == 1)
        #expect(repository.loadCount == 1)
        #expect(repository.appliedSnapshotHashes == ["snapshot-1"])
        #expect(completed)
    }

    @Test func failedPreviewCanBeRetriedWithoutRecreatingViewModel() async {
        let repository = SeasonRepairRepositoryFake()
        repository.preview = makePreview()
        repository.shouldFailLoad = true
        let viewModel = makeViewModel(repository: repository)

        await viewModel.start()
        #expect(viewModel.preview == nil)
        #expect(viewModel.errorMessage == "시즌 변경 미리보기를 준비하지 못했습니다.")

        repository.shouldFailLoad = false
        await viewModel.start()
        #expect(viewModel.preview?.resultingPostCount == 3)
        #expect(repository.requestCount == 2)
    }

    @Test func noChangePreviewReturnsWithoutRequiringApply() async {
        let repository = SeasonRepairRepositoryFake()
        repository.preview = LookbookSeasonRepairPreview(
            jobID: "job-1",
            brandID: BrandID(value: "brand-1"),
            seasonID: SeasonID(value: "season-1"),
            generation: 2,
            snapshotHash: "snapshot-no-changes",
            keep: [
                LookbookSeasonRepairExistingEntry(
                    postID: "post-1",
                    sourceURL: URL(string: "https://example.com/1.jpg")!,
                    previousIndex: 0,
                    proposedIndex: 0,
                    matchedBy: .canonicalURL
                )
            ],
            add: [],
            reorder: [],
            removeCandidates: [],
            resultingPostCount: 1
        )
        var completed = false
        let viewModel = makeViewModel(
            repository: repository,
            onCompleted: { completed = true }
        )

        await viewModel.start()

        #expect(viewModel.preview == nil)
        #expect(completed)
        #expect(repository.appliedSnapshotHashes.isEmpty)
    }

    private func makeViewModel(
        repository: SeasonRepairRepositoryFake,
        onCompleted: @escaping () -> Void = {}
    ) -> LookbookSeasonRepairViewModel {
        LookbookSeasonRepairViewModel(
            brandID: BrandID(value: "brand-1"),
            seasonID: SeasonID(value: "season-1"),
            sourceImportJobID: "job-1",
            useCase: ManageLookbookSeasonRepairUseCase(repository: repository),
            pollDelayNanoseconds: 0,
            maxPollAttempts: 1,
            onCompleted: onCompleted
        )
    }

    private func makePreview() -> LookbookSeasonRepairPreview {
        LookbookSeasonRepairPreview(
            jobID: "job-1",
            brandID: BrandID(value: "brand-1"),
            seasonID: SeasonID(value: "season-1"),
            generation: 1,
            snapshotHash: "snapshot-1",
            keep: [],
            add: [
                LookbookSeasonRepairAddEntry(
                    postID: "repair-1",
                    candidateKey: "candidate-1",
                    sourceURL: URL(string: "https://example.com/1.jpg")!,
                    proposedIndex: 0,
                    alt: nil,
                    contentHash: nil
                )
            ],
            reorder: [],
            removeCandidates: [],
            resultingPostCount: 3
        )
    }
}

@MainActor
private final class SeasonRepairRepositoryFake:
    LookbookSeasonRepairRepositoryProtocol {
    private enum Failure: Error {
        case requested
    }

    var preview: LookbookSeasonRepairPreview!
    var shouldFailLoad = false
    var requestCount = 0
    var loadCount = 0
    var appliedSnapshotHashes: [String] = []

    func requestRepair(
        brandID: BrandID,
        seasonID: SeasonID,
        sourceImportJobID: String
    ) async throws -> LookbookSeasonRepairReceipt {
        requestCount += 1
        return LookbookSeasonRepairReceipt(
            jobID: sourceImportJobID,
            seasonID: seasonID,
            generation: 1,
            status: .analyzing,
            duplicate: false
        )
    }

    func loadPreview(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookSeasonRepairPreview {
        loadCount += 1
        if shouldFailLoad {
            throw Failure.requested
        }
        return preview
    }

    func applyRepair(
        brandID: BrandID,
        preview: LookbookSeasonRepairPreview
    ) async throws -> LookbookSeasonRepairReceipt {
        appliedSnapshotHashes.append(preview.snapshotHash)
        return LookbookSeasonRepairReceipt(
            jobID: preview.jobID,
            seasonID: preview.seasonID,
            generation: preview.generation,
            status: .applied,
            duplicate: false
        )
    }
}
