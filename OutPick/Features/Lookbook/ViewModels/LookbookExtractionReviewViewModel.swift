import Foundation

@MainActor
final class LookbookExtractionReviewViewModel: ObservableObject {
    @Published private(set) var review: LookbookExtractionReview?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published var excludedCandidateKeys: Set<String> = []
    @Published var expectedCandidateCountText = ""
    @Published var note = ""

    private let brandID: BrandID
    private let jobID: String
    private let useCase: any ManageLookbookExtractionReviewUseCaseProtocol
    private let onCompleted: () -> Void

    init(
        brandID: BrandID,
        jobID: String,
        useCase: any ManageLookbookExtractionReviewUseCaseProtocol,
        onCompleted: @escaping () -> Void
    ) {
        self.brandID = brandID
        self.jobID = jobID
        self.useCase = useCase
        self.onCompleted = onCompleted
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            review = try await useCase.load(brandID: brandID, jobID: jobID)
        } catch {
            errorMessage = "검토 정보를 불러오지 못했습니다."
        }
    }

    func toggle(candidateKey: String) {
        if excludedCandidateKeys.contains(candidateKey) {
            excludedCandidateKeys.remove(candidateKey)
        } else {
            excludedCandidateKeys.insert(candidateKey)
        }
    }

    func approve() async {
        guard let review, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await useCase.approve(
                brandID: brandID,
                review: review,
                excludedCandidateKeys: Array(excludedCandidateKeys)
            )
            onCompleted()
        } catch {
            errorMessage = "검토 결과를 승인하지 못했습니다."
        }
    }

    func reportInsufficientImages() async {
        guard let review, !isSubmitting else { return }
        let expectedCount = Int(expectedCandidateCountText)
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await useCase.reportInsufficientImages(
                brandID: brandID,
                review: review,
                expectedCandidateCount: expectedCount,
                note: note
            )
            await load()
        } catch {
            errorMessage = "이미지 부족 결과를 저장하지 못했습니다."
        }
    }

    func reanalyze() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await useCase.reanalyze(brandID: brandID, jobID: jobID)
            onCompleted()
        } catch {
            errorMessage = "재분석을 요청하지 못했습니다."
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
