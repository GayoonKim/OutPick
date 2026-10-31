import FirebaseFirestore
import Foundation
import Testing
import UIKit
@testable import OutPick

@MainActor
struct LookbookHomeViewModelInterestTests {
    @Test func requestEntryRoutesWithAndWithoutSearchResultsAtLimit20() async throws {
        for hasResults in [true, false] {
            let brand = homeBrand("mono", moodIDs: [])
            let search = HomeSearchUseCaseFake(brands: hasResults ? [brand] : [])
            let model = makeViewModel(mainBrands: [brand], interestUseCase: HomeInterestUseCaseFake(results: []),
                                      store: CurrentUserStylePreferenceStore(), searchUseCase: search)
            model.searchText = " Mono "
            for _ in 0..<100 {
                if model.canRequestBrand { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            #expect(model.searchPhase == (hasResults ? .results : .empty))
            #expect(search.limits == [20])
            let spy = HomeRequestCoordinatorSpy()
            model.requestBrand(using: spy)
            #expect(spy.names == ["Mono"])
        }
    }

    @Test
    func brandMetadataAppearsWithoutLogoRequests() async {
        let cache = BlockingHomeImageCache()
        let viewModel = makeViewModel(
            mainBrands: [homeBrand("brand-with-logo", moodIDs: [], logoThumbPath: "brands/logo-thumb")],
            interestUseCase: HomeInterestUseCaseFake(results: []),
            store: CurrentUserStylePreferenceStore(),
            imageCache: cache
        )
        await viewModel.loadInitialPageIfNeeded()
        viewModel.updateViewport(indices: [0], searching: false)
        await Task.yield()
        #expect(await cache.requestCount == 0)

        #expect(viewModel.phase == .ready)
        #expect(viewModel.brands.map(\.id.value) == ["brand-with-logo"])

    }

    @Test
    func noStylePreferenceKeepsUnconfiguredWithoutQuery() async {
        let interestUseCase = HomeInterestUseCaseFake(results: [])
        let viewModel = makeViewModel(
            mainBrands: [homeBrand("all-brand", moodIDs: [])],
            interestUseCase: interestUseCase,
            store: CurrentUserStylePreferenceStore()
        )

        await viewModel.loadInitialPageIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.interestPhase == .unconfigured)
        #expect(interestUseCase.requests.isEmpty)
    }

    @Test
    func emptyInterestResultKeepsMainBrandListReady() async {
        let mainBrand = homeBrand("all-brand", moodIDs: [])
        let interestUseCase = HomeInterestUseCaseFake(results: [
            .success(InterestedStyleBrandPage(items: [], nextCursor: nil))
        ])
        let viewModel = makeViewModel(
            mainBrands: [mainBrand],
            interestUseCase: interestUseCase,
            store: CurrentUserStylePreferenceStore(
                selectedMoodIDs: ["minimal"]
            )
        )

        await viewModel.loadInitialPageIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.brands.map(\.id.value) == ["all-brand"])
        #expect(viewModel.interestPhase == .empty)
        #expect(interestUseCase.requests.first?.limit == 10)
        #expect(interestUseCase.requests.first?.cursor == nil)
    }

    @Test
    func interestFailureDoesNotFailMainBrandList() async {
        let interestUseCase = HomeInterestUseCaseFake(results: [
            .failure(HomeInterestTestError.failed)
        ])
        let viewModel = makeViewModel(
            mainBrands: [homeBrand("all-brand", moodIDs: [])],
            interestUseCase: interestUseCase,
            store: CurrentUserStylePreferenceStore(
                selectedMoodIDs: ["minimal"]
            )
        )

        await viewModel.loadInitialPageIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(
            viewModel.interestPhase ==
                .failed("관심 스타일 브랜드를 불러오지 못했어요")
        )
    }

    @Test
    func preferenceChangeReloadsInterestedBrands() async throws {
        let minimalBrand = homeBrand("minimal-brand", moodIDs: ["minimal"])
        let streetBrand = homeBrand("street-brand", moodIDs: ["street"])
        let store = CurrentUserStylePreferenceStore(selectedMoodIDs: ["minimal"])
        let interestUseCase = HomeInterestUseCaseFake(results: [
            .success(InterestedStyleBrandPage(items: [minimalBrand], nextCursor: nil)),
            .success(InterestedStyleBrandPage(items: [streetBrand], nextCursor: nil))
        ])
        let viewModel = makeViewModel(
            mainBrands: [minimalBrand, streetBrand],
            interestUseCase: interestUseCase,
            store: store
        )
        await viewModel.loadInitialPageIfNeeded()

        store.replace(selectedMoodIDs: ["street"])
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(viewModel.interestedStyleBrands.map(\.id.value) == ["street-brand"])
        #expect(interestUseCase.requests.map(\.moodIDs) == [["minimal"], ["street"]])
    }

    private func makeViewModel(
        mainBrands: [Brand],
        interestUseCase: HomeInterestUseCaseFake,
        store: CurrentUserStylePreferenceStore,
        imageCache: (any BrandImageCacheProtocol)? = nil,
        searchUseCase: HomeSearchUseCaseFake = HomeSearchUseCaseFake()
    ) -> LookbookHomeViewModel {
        LookbookHomeViewModel(
            repo: HomeBrandRepositoryFake(brands: mainBrands),
            searchUseCase: searchUseCase,
            loadInterestedStyleBrandsUseCase: interestUseCase,
            stylePreferenceStore: store,
            brandAdminSessionStore: BrandAdminSessionStore(
                capabilitiesClient: HomeBrandCapabilitiesClientFake()
            ),
            brandImageCache: imageCache ?? HomeBrandImageCacheFake(),
            initialBrandLimit: 12
        )
    }
}

private final class HomeInterestUseCaseFake:
    LoadInterestedStyleBrandsUseCaseProtocol {
    struct Request {
        let moodIDs: [String]
        let limit: Int
        let cursor: InterestedStyleBrandCursor?
    }

    private var results: [Result<InterestedStyleBrandPage, Error>]
    private(set) var requests: [Request] = []

    init(results: [Result<InterestedStyleBrandPage, Error>]) {
        self.results = results
    }

    func execute(
        moodIDs: [String],
        limit: Int,
        after cursor: InterestedStyleBrandCursor?
    ) async throws -> InterestedStyleBrandPage {
        requests.append(
            Request(moodIDs: moodIDs, limit: limit, cursor: cursor)
        )
        guard results.isEmpty == false else {
            return InterestedStyleBrandPage(items: [], nextCursor: nil)
        }
        return try results.removeFirst().get()
    }
}

private final class HomeBrandRepositoryFake: BrandRepositoryProtocol {
    private let brands: [Brand]

    init(brands: [Brand]) {
        self.brands = brands
    }

    func fetchBrand(brandID: BrandID) async throws -> Brand {
        guard let brand = brands.first(where: { $0.id == brandID }) else {
            throw HomeInterestTestError.failed
        }
        return brand
    }

    func fetchBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        BrandPage(items: brands, last: nil)
    }

    func fetchFeaturedBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        BrandPage(items: [], last: nil)
    }

    func fetchInterestedStyleBrands(
        moodIDs: [String],
        limit: Int,
        after cursor: InterestedStyleBrandCursor?
    ) async throws -> InterestedStyleBrandPage {
        throw HomeInterestTestError.failed
    }
}

private final class HomeSearchUseCaseFake: SearchBrandsUseCaseProtocol {
    let brands: [Brand]
    var limits: [Int] = []
    init(brands: [Brand] = []) { self.brands = brands }
    func execute(query: String, limit: Int) async throws -> [Brand] {
        limits.append(limit)
        return brands
    }
}

@MainActor
private final class HomeRequestCoordinatorSpy: BrandRequestRouting {
    var names: [String] = []
    func pushBrandRequest(initialBrandName: String) { names.append(initialBrandName) }
    func pushBrandDetail(brand: Brand) {}
}

private struct HomeBrandCapabilitiesClientFake: BrandAdminCapabilitiesCalling {
    func getBrandAdminCapabilities() async throws -> BrandAdminCapabilitiesResponse {
        BrandAdminCapabilitiesResponse(
            isTotalAdmin: false,
            roles: [],
            ownedBrandIDs: [],
            adminBrandIDs: []
        )
    }
}

private struct HomeBrandImageCacheFake: BrandImageCacheProtocol {
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

private actor BlockingHomeImageCache: BrandImageCacheProtocol {
    private var didStart = false
    private(set) var requestCount = 0
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitUntilPrefetchStarted() async {
        if didStart { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func releasePrefetch() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage { UIImage() }
    func storeImageData(_ data: Data, path: String) async throws {}
    func removeImage(path: String) async {}
    func prefetch(items: [(path: String, maxBytes: Int)], concurrency: Int, storePolicy: ImageCacheStorePolicy) async {
        requestCount += 1
        didStart = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func prefetchAssets(items: [LookbookAssetImageRequest], concurrency: Int, storePolicy: ImageCacheStorePolicy) async {
        didStart = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }
}

private enum HomeInterestTestError: Error {
    case failed
}

private func homeBrand(
    _ id: String,
    moodIDs: [String],
    likeCount: Int = 0,
    logoThumbPath: String? = nil
) -> Brand {
    Brand(
        id: BrandID(value: id),
        name: id,
        englishName: nil,
        websiteURL: nil,
        lookbookArchiveURL: nil,
        logoThumbPath: logoThumbPath,
        logoDetailPath: nil,
        logoOriginalPath: nil,
        isFeatured: false,
        moodIDs: moodIDs,
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
        updatedAt: Date(timeIntervalSince1970: 0),
        publicationStatus: "public"
    )
}
