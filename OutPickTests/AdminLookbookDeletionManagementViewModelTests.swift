import FirebaseFirestore
import Foundation
import Testing
@testable import OutPick

@MainActor
struct AdminLookbookDeletionManagementViewModelTests {
    @Test func reloadReplacesFirstPageAndStoresNextCursor() async {
        let repository = DeletionRepositoryFake(pages: [
            page([request("request-1")], next: cursor("request-1"))
        ])
        let viewModel = makeViewModel(deletionRepository: repository)

        await viewModel.reloadDeletionRequests(isTotalAdmin: true)

        #expect(viewModel.deletionRequests.map(\.requestID) == ["request-1"])
        #expect(viewModel.hasMoreDeletionRequests)
        #expect(repository.listCallCount == 1)
    }

    @Test func nextPageAppendRemovesDuplicateRequestIDs() async {
        let repository = DeletionRepositoryFake(pages: [
            page([request("request-1"), request("request-2")], next: cursor("request-2")),
            page([request("request-2"), request("request-3")], next: nil)
        ])
        let viewModel = makeViewModel(deletionRepository: repository)

        await viewModel.reloadDeletionRequests(isTotalAdmin: true)
        await viewModel.loadMoreDeletionRequestsIfNeeded(isTotalAdmin: true)
        await viewModel.loadMoreDeletionRequestsIfNeeded(isTotalAdmin: true)

        #expect(viewModel.deletionRequests.map(\.requestID) == ["request-1", "request-2", "request-3"])
        #expect(viewModel.hasMoreDeletionRequests == false)
        #expect(repository.listCallCount == 2)
    }

    @Test func retryIsRestrictedToTotalAdminAndFailedStatus() async {
        let failedRequest = request("request-failed", status: .failed)
        let repository = DeletionRepositoryFake(pages: [
            page([failedRequest], next: nil)
        ])
        let viewModel = makeViewModel(deletionRepository: repository)

        await viewModel.retryFailedPurge(failedRequest, isTotalAdmin: false)
        await viewModel.retryFailedPurge(request("request-active"), isTotalAdmin: true)
        await viewModel.retryFailedPurge(failedRequest, isTotalAdmin: true)

        #expect(repository.retriedRequestIDs == ["request-failed"])
        #expect(viewModel.message == "삭제를 다시 처리합니다.")
    }

    @Test func concurrentNextPageRequestsCallRepositoryOnce() async {
        let repository = DeletionRepositoryFake(
            pages: [
                page([request("request-1")], next: cursor("request-1")),
                page([request("request-2")], next: nil)
            ],
            listDelayNanoseconds: 100_000_000
        )
        let viewModel = makeViewModel(deletionRepository: repository)
        await viewModel.reloadDeletionRequests(isTotalAdmin: true)

        async let first: Void = viewModel.loadMoreDeletionRequestsIfNeeded(isTotalAdmin: true)
        async let second: Void = viewModel.loadMoreDeletionRequestsIfNeeded(isTotalAdmin: true)
        _ = await (first, second)

        #expect(repository.listCallCount == 2)
        #expect(viewModel.deletionRequests.map(\.requestID) == ["request-1", "request-2"])
    }

    @Test func retryDisplayStateCombinesAutomaticManualAndLeaseStates() {
        let finalFailure = request("final", status: .failed)
        let automaticRetry = request(
            "automatic",
            status: .failed,
            autoRetryEligible: true
        )
        let queuedRetry = request(
            "queued",
            status: .failed,
            manualRetryState: .queued
        )
        let leasedRetry = request(
            "leased",
            status: .failed,
            purgeInProgress: true
        )

        #expect(finalFailure.isPurgeRetryPendingOrInProgress == false)
        #expect(automaticRetry.isPurgeRetryPendingOrInProgress)
        #expect(automaticRetry.isPurgeRetryInProgress == false)
        #expect(queuedRetry.isPurgeRetryInProgress)
        #expect(leasedRetry.isPurgeRetryInProgress)
    }

    private func makeViewModel(
        deletionRepository: DeletionRepositoryFake
    ) -> AdminLookbookDeletionManagementViewModel {
        AdminLookbookDeletionManagementViewModel(
            brandRepository: DeletionBrandRepositoryStub(),
            searchUseCase: DeletionSearchBrandsUseCaseStub(),
            seasonRepository: DeletionSeasonRepositoryStub(),
            postRepository: DeletionPostRepositoryStub(),
            deletionRepository: deletionRepository
        )
    }

    private func cursor(_ requestID: String) -> LookbookDeletionRequestPage.Cursor {
        .init(updatedAt: "2026-07-13T00:00:00.000Z", requestID: requestID)
    }

    private func page(
        _ requests: [LookbookDeletionRequest],
        next: LookbookDeletionRequestPage.Cursor?
    ) -> LookbookDeletionRequestPage {
        .init(requests: requests, nextCursor: next)
    }

    private func request(
        _ requestID: String,
        status: LookbookDeletionRequestStatus = .active,
        autoRetryEligible: Bool = false,
        manualRetryState: LookbookDeletionManualRetryState? = nil,
        purgeInProgress: Bool = false
    ) -> LookbookDeletionRequest {
        LookbookDeletionRequest(
            requestID: requestID,
            targetType: .post,
            targetID: requestID,
            targetPath: "brands/brand-1/seasons/season-1/posts/\(requestID)",
            brandID: BrandID(value: "brand-1"),
            seasonID: SeasonID(value: "season-1"),
            postID: PostID(value: requestID),
            status: status,
            requestedBy: UserID(value: "user-1"),
            requestedAt: nil,
            restoreUntil: nil,
            purgeAfter: nil,
            reason: nil,
            cancelledBy: nil,
            cancelledAt: nil,
            restoredBy: nil,
            restoredAt: nil,
            updatedBy: nil,
            updatedAt: nil,
            targetDisplayName: nil,
            targetImagePath: nil,
            brandName: "Brand",
            brandEnglishName: nil,
            brandLogoThumbPath: nil,
            seasonTitle: "Season",
            seasonCoverThumbPath: nil,
            postCaption: nil,
            postImageThumbPath: nil,
            autoRetryEligible: autoRetryEligible,
            retryAfter: nil,
            purgeAttemptCount: 0,
            purgeErrorMessage: nil,
            manualRetryState: manualRetryState,
            manualRetryCount: 0,
            purgeInProgress: purgeInProgress
        )
    }
}

@MainActor
private final class DeletionRepositoryFake: LookbookDeletionRepositoryProtocol {
    private var pages: [LookbookDeletionRequestPage]
    private let listDelayNanoseconds: UInt64
    private(set) var listCallCount = 0
    private(set) var retriedRequestIDs: [String] = []

    init(
        pages: [LookbookDeletionRequestPage],
        listDelayNanoseconds: UInt64 = 0
    ) {
        self.pages = pages
        self.listDelayNanoseconds = listDelayNanoseconds
    }

    func listDeletionRequests(
        targetType: LookbookDeletionTargetType?,
        brandID: BrandID?,
        limit: Int,
        cursor: LookbookDeletionRequestPage.Cursor?
    ) async throws -> LookbookDeletionRequestPage {
        if listDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: listDelayNanoseconds)
        }
        defer { listCallCount += 1 }
        return pages[min(listCallCount, pages.count - 1)]
    }

    func retryFailedPurge(requestID: String) async throws -> LookbookDeletionRetryReceipt {
        retriedRequestIDs.append(requestID)
        return .init(requestID: requestID, manualRetryState: .queued, duplicate: false)
    }

    func requestBrandDeletion(brandID: BrandID, reason: String?) async throws -> LookbookDeletionMutationReceipt { throw StubError.unused }
    func cancelBrandDeletion(brandID: BrandID) async throws -> LookbookDeletionMutationReceipt { throw StubError.unused }
    func softDeleteSeason(brandID: BrandID, seasonID: SeasonID, reason: String?) async throws -> LookbookDeletionMutationReceipt { throw StubError.unused }
    func batchSoftDeleteSeasons(brandID: BrandID, seasonIDs: [SeasonID], reason: String?) async throws -> LookbookDeletionBatchResult { throw StubError.unused }
    func restoreSeason(brandID: BrandID, seasonID: SeasonID) async throws -> LookbookDeletionMutationReceipt { throw StubError.unused }
    func softDeletePost(brandID: BrandID, seasonID: SeasonID, postID: PostID, reason: String?) async throws -> LookbookDeletionMutationReceipt { throw StubError.unused }
    func batchSoftDeletePosts(brandID: BrandID, seasonID: SeasonID, postIDs: [PostID], reason: String?) async throws -> LookbookDeletionBatchResult { throw StubError.unused }
    func restorePost(brandID: BrandID, seasonID: SeasonID, postID: PostID) async throws -> LookbookDeletionMutationReceipt { throw StubError.unused }
}

private struct DeletionBrandRepositoryStub: BrandRepositoryProtocol {
    func fetchBrand(brandID: BrandID) async throws -> Brand { throw StubError.unused }
    func fetchBrands(sort: BrandSort?, limit: Int, after last: DocumentSnapshot?) async throws -> BrandPage { throw StubError.unused }
    func fetchFeaturedBrands(sort: BrandSort?, limit: Int, after last: DocumentSnapshot?) async throws -> BrandPage { throw StubError.unused }
}

private struct DeletionSearchBrandsUseCaseStub: SearchBrandsUseCaseProtocol {
    func execute(query: String, limit: Int) async throws -> [Brand] { [] }
}

private struct DeletionSeasonRepositoryStub: SeasonRepositoryProtocol {
    func createSeason(brandID: BrandID, year: Int, term: SeasonTerm, description: String, coverImageData: Data?, tagIDs: [TagID], tagConceptIDs: [String]?) async throws -> Season { throw StubError.unused }
    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season { throw StubError.unused }
    func fetchSeasons(brandID: BrandID, pageSize: Int, after last: DocumentSnapshot?) async throws -> SeasonPage { throw StubError.unused }
    func fetchAllSeasons(brandID: BrandID) async throws -> [Season] { [] }
}

private struct DeletionPostRepositoryStub: PostRepositoryProtocol {
    func fetchPosts(brandID: BrandID, seasonID: SeasonID, sort: PostSortOption, filterTagIDs: [TagID], page: PageRequest) async throws -> PageResponse<LookbookPost> { throw StubError.unused }
    func fetchPost(brandID: BrandID, seasonID: SeasonID, postID: PostID) async throws -> LookbookPost { throw StubError.unused }
    func fetchPostsByTag(tagID: TagID, sort: PostSortOption, page: PageRequest) async throws -> PageResponse<LookbookPost> { throw StubError.unused }
}

private enum StubError: Error {
    case unused
}
