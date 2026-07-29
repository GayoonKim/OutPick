import Foundation
import Testing
import UIKit
@testable import OutPick

@MainActor
struct InterestedStyleBrandListViewModelTests {
    @Test
    func nextPageAppendsOnlyNewBrandIDs() async {
        let first = listBrand("brand-1", likeCount: 4)
        let second = listBrand("brand-2", likeCount: 3)
        let firstCursor = InterestedStyleBrandCursor(
            likeCount: first.metrics.likeCount,
            brandID: first.id
        )
        let useCase = InterestedStyleBrandLoadUseCaseFake(pages: [
            InterestedStyleBrandPage(
                items: [first, second],
                nextCursor: nil
            )
        ])
        let viewModel = makeListViewModel(
            initialBrands: [first],
            initialCursor: firstCursor,
            useCase: useCase,
            store: CurrentUserStylePreferenceStore(selectedMoodIDs: ["minimal"])
        )

        await viewModel.loadNextPageIfNeeded(current: first)

        #expect(viewModel.brands.map(\.id.value) == ["brand-1", "brand-2"])
        #expect(useCase.requests.count == 1)
        #expect(useCase.requests.first?.limit == 20)
        #expect(useCase.requests.first?.cursor == firstCursor)
    }

    @Test
    func concurrentNextPageRequestsUseSameCursorOnce() async {
        let first = listBrand("brand-1", likeCount: 4)
        let second = listBrand("brand-2", likeCount: 3)
        let cursor = InterestedStyleBrandCursor(
            likeCount: first.metrics.likeCount,
            brandID: first.id
        )
        let useCase = InterestedStyleBrandLoadUseCaseFake(
            pages: [
                InterestedStyleBrandPage(items: [second], nextCursor: nil)
            ],
            delayNanoseconds: 100_000_000
        )
        let viewModel = makeListViewModel(
            initialBrands: [first],
            initialCursor: cursor,
            useCase: useCase,
            store: CurrentUserStylePreferenceStore(selectedMoodIDs: ["minimal"])
        )

        async let firstRequest: Void = viewModel.loadNextPageIfNeeded(current: first)
        async let secondRequest: Void = viewModel.loadNextPageIfNeeded(current: first)
        _ = await (firstRequest, secondRequest)

        #expect(useCase.requests.count == 1)
        #expect(viewModel.brands.map(\.id.value) == ["brand-1", "brand-2"])
    }

    @Test
    func preferenceChangeRefreshesFromFirstPage() async throws {
        let first = listBrand("brand-1", likeCount: 4)
        let replacement = listBrand("brand-3", likeCount: 8)
        let store = CurrentUserStylePreferenceStore(selectedMoodIDs: ["minimal"])
        let useCase = InterestedStyleBrandLoadUseCaseFake(pages: [
            InterestedStyleBrandPage(items: [replacement], nextCursor: nil)
        ])
        let viewModel = makeListViewModel(
            initialBrands: [first],
            initialCursor: nil,
            useCase: useCase,
            store: store
        )

        store.replace(selectedMoodIDs: ["street"])
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(viewModel.brands.map(\.id.value) == ["brand-3"])
        #expect(useCase.requests.first?.moodIDs == ["street"])
    }

    @Test
    func newerPreferenceRefreshDiscardsOlderResponse() async throws {
        let first = listBrand("brand-1", likeCount: 4)
        let stale = listBrand("stale-brand", likeCount: 9)
        let latest = listBrand("latest-brand", likeCount: 8)
        let store = CurrentUserStylePreferenceStore(selectedMoodIDs: ["minimal"])
        let useCase = InterestedStyleBrandLoadUseCaseFake(responses: [
            .init(
                result: .success(
                    InterestedStyleBrandPage(items: [stale], nextCursor: nil)
                ),
                delayNanoseconds: 150_000_000
            ),
            .init(
                result: .success(
                    InterestedStyleBrandPage(items: [latest], nextCursor: nil)
                ),
                delayNanoseconds: 10_000_000
            )
        ])
        let viewModel = makeListViewModel(
            initialBrands: [first],
            initialCursor: nil,
            useCase: useCase,
            store: store
        )

        store.replace(selectedMoodIDs: ["street"])
        try await Task.sleep(nanoseconds: 20_000_000)
        store.replace(selectedMoodIDs: ["formal"])
        try await Task.sleep(nanoseconds: 180_000_000)

        #expect(viewModel.brands.map(\.id.value) == ["latest-brand"])
        #expect(useCase.requests.map(\.moodIDs) == [["street"], ["formal"]])
    }

    @Test
    func loadMoreFailureKeepsItemsAndCanRetrySameCursor() async {
        let first = listBrand("brand-1", likeCount: 4)
        let second = listBrand("brand-2", likeCount: 3)
        let cursor = InterestedStyleBrandCursor(
            likeCount: first.metrics.likeCount,
            brandID: first.id
        )
        let useCase = InterestedStyleBrandLoadUseCaseFake(responses: [
            .init(result: .failure(InterestedStyleBrandListTestError.failed)),
            .init(
                result: .success(
                    InterestedStyleBrandPage(items: [second], nextCursor: nil)
                )
            )
        ])
        let viewModel = makeListViewModel(
            initialBrands: [first],
            initialCursor: cursor,
            useCase: useCase,
            store: CurrentUserStylePreferenceStore(selectedMoodIDs: ["minimal"])
        )

        await viewModel.loadNextPageIfNeeded(current: first)

        #expect(viewModel.brands.map(\.id.value) == ["brand-1"])
        #expect(viewModel.loadMoreErrorMessage == "다음 브랜드를 불러오지 못했어요")

        await viewModel.retryLoadMore()

        #expect(viewModel.brands.map(\.id.value) == ["brand-1", "brand-2"])
        #expect(useCase.requests.map(\.cursor) == [cursor, cursor])
    }

    private func makeListViewModel(
        initialBrands: [Brand],
        initialCursor: InterestedStyleBrandCursor?,
        useCase: InterestedStyleBrandLoadUseCaseFake,
        store: CurrentUserStylePreferenceStore
    ) -> InterestedStyleBrandListViewModel {
        InterestedStyleBrandListViewModel(
            initialBrands: initialBrands,
            initialCursor: initialCursor,
            loadUseCase: useCase,
            stylePreferenceStore: store,
            brandImageCache: InterestedBrandImageCacheStub(),
            pageSize: 20
        )
    }
}

private final class InterestedStyleBrandLoadUseCaseFake:
    LoadInterestedStyleBrandsUseCaseProtocol {
    struct Response {
        let result: Result<InterestedStyleBrandPage, Error>
        let delayNanoseconds: UInt64

        init(
            result: Result<InterestedStyleBrandPage, Error>,
            delayNanoseconds: UInt64 = 0
        ) {
            self.result = result
            self.delayNanoseconds = delayNanoseconds
        }
    }

    struct Request {
        let moodIDs: [String]
        let limit: Int
        let cursor: InterestedStyleBrandCursor?
    }

    private var responses: [Response]
    private(set) var requests: [Request] = []

    init(
        pages: [InterestedStyleBrandPage],
        delayNanoseconds: UInt64 = 0
    ) {
        responses = pages.map {
            Response(
                result: .success($0),
                delayNanoseconds: delayNanoseconds
            )
        }
    }

    init(responses: [Response]) {
        self.responses = responses
    }

    func execute(
        moodIDs: [String],
        limit: Int,
        after cursor: InterestedStyleBrandCursor?
    ) async throws -> InterestedStyleBrandPage {
        requests.append(Request(moodIDs: moodIDs, limit: limit, cursor: cursor))
        guard responses.isEmpty == false else {
            return InterestedStyleBrandPage(items: [], nextCursor: nil)
        }
        let response = responses.removeFirst()
        if response.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: response.delayNanoseconds)
        }
        return try response.result.get()
    }
}

private enum InterestedStyleBrandListTestError: Error {
    case failed
}

private struct InterestedBrandImageCacheStub: BrandImageCacheProtocol {
    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        UIImage()
    }

    func storeImageData(_ data: Data, path: String) async throws {}
    func removeImage(path: String) async {}

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async {}
}

private func listBrand(_ id: String, likeCount: Int) -> Brand {
    Brand(
        id: BrandID(value: id),
        name: id,
        englishName: nil,
        websiteURL: nil,
        lookbookArchiveURL: nil,
        logoThumbPath: nil,
        logoDetailPath: nil,
        logoOriginalPath: nil,
        isFeatured: false,
        moodIDs: ["minimal"],
        discoveryStatus: .idle,
        lastDiscoveryErrorMessage: nil,
        lastDiscoveryRequestedAt: nil,
        lastDiscoveryCompletedAt: nil,
        metrics: BrandMetrics(
            likeCount: likeCount,
            viewCount: 0,
            popularScore: 0
        ),
        deletionStatus: .active,
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}
