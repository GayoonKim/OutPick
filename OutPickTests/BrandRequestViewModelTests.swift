import Testing
@testable import OutPick

@MainActor
struct BrandRequestViewModelTests {
    @Test func interactivePopIsBlockedOnlyAfterDraftChanges() {
        let viewModel = BrandRequestViewModel(
            initialBrandName: "Acne Studios",
            submitUseCase: BrandRequestSubmitUseCaseStub(),
            loadBrandUseCase: BrandRequestLoadUseCaseStub()
        )

        #expect(viewModel.hasDraftChanges == false)
        #expect(viewModel.disablesInteractivePop == false)

        viewModel.brandName = "  Acne Studios  "
        #expect(viewModel.hasDraftChanges == false)

        viewModel.englishBrandName = "Acne Studios"
        #expect(viewModel.hasDraftChanges)
        #expect(viewModel.disablesInteractivePop)

        viewModel.englishBrandName = ""
        viewModel.brandName = "Acne"
        #expect(viewModel.hasDraftChanges)
        #expect(viewModel.disablesInteractivePop)
    }
}

private struct BrandRequestLoadUseCaseStub: LoadPublicBrandUseCaseProtocol {
    func execute(brandID: BrandID) async throws -> Brand {
        throw LookbookContentUnavailableError.brandUnavailable
    }
}

private struct BrandRequestSubmitUseCaseStub: SubmitBrandRequestUseCaseProtocol {
    func execute(
        brandName: String,
        websiteURL: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt {
        fatalError("이 테스트에서는 제출하지 않습니다.")
    }
}
