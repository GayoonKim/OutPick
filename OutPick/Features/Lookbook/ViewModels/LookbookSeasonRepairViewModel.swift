import Foundation

@MainActor
final class LookbookSeasonRepairViewModel: ObservableObject {
    @Published private(set) var preview: LookbookSeasonRepairPreview?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?

    private let brandID: BrandID
    private let seasonID: SeasonID
    private let sourceImportJobID: String
    private let useCase: any ManageLookbookSeasonRepairUseCaseProtocol
    private let pollDelayNanoseconds: UInt64
    private let maxPollAttempts: Int
    private let onCompleted: () -> Void

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        sourceImportJobID: String,
        useCase: any ManageLookbookSeasonRepairUseCaseProtocol,
        pollDelayNanoseconds: UInt64 = 1_000_000_000,
        maxPollAttempts: Int = 60,
        onCompleted: @escaping () -> Void
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.sourceImportJobID = sourceImportJobID
        self.useCase = useCase
        self.pollDelayNanoseconds = pollDelayNanoseconds
        self.maxPollAttempts = maxPollAttempts
        self.onCompleted = onCompleted
    }

    func start() async {
        guard !isLoading, preview == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let receipt = try await useCase.request(
                brandID: brandID,
                seasonID: seasonID,
                sourceImportJobID: sourceImportJobID
            )
            let loadedPreview = try await waitForPreview(jobID: receipt.jobID)
            if loadedPreview.hasChanges {
                preview = loadedPreview
            } else {
                onCompleted()
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "시즌 변경 미리보기를 준비하지 못했습니다."
        }
    }

    func apply() async {
        guard let preview, !isApplying else { return }
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        do {
            _ = try await useCase.apply(brandID: brandID, preview: preview)
            onCompleted()
        } catch {
            errorMessage = "시즌 변경 사항을 적용하지 못했습니다."
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func waitForPreview(
        jobID: String
    ) async throws -> LookbookSeasonRepairPreview {
        var lastError: Error?
        for attempt in 0..<maxPollAttempts {
            do {
                return try await useCase.loadPreview(
                    brandID: brandID,
                    jobID: jobID
                )
            } catch {
                lastError = error
                guard attempt + 1 < maxPollAttempts else { break }
                try await Task.sleep(nanoseconds: pollDelayNanoseconds)
            }
        }
        throw lastError ?? CancellationError()
    }
}
