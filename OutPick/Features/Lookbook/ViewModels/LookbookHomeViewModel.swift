//
//  LookbookHomeViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class LookbookHomeViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    enum SearchPhase: Equatable {
        case idle
        case searching
        case results
        case empty
        case failed(String)
    }

    enum InterestPhase: Equatable {
        case idle
        case loading
        case ready
        case unconfigured
        case empty
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var brands: [Brand] = []
    @Published var searchText: String = ""
    @Published private(set) var searchPhase: SearchPhase = .idle
    @Published private(set) var searchResults: [Brand] = []
    @Published private(set) var canOpenAdminConsole: Bool = false
    @Published private(set) var interestPhase: InterestPhase = .idle
    @Published private(set) var interestedStyleBrands: [Brand] = []
    @Published private(set) var interestedStyleNextCursor: InterestedStyleBrandCursor?

    /// DI
    private let repo: BrandRepositoryProtocol
    private let searchUseCase: any SearchBrandsUseCaseProtocol
    private let loadInterestedStyleBrandsUseCase: any LoadInterestedStyleBrandsUseCaseProtocol
    private let stylePreferenceStore: CurrentUserStylePreferenceStore
    private let brandAdminSessionStore: BrandAdminSessionStore
    let brandImageCache: any BrandImageCacheProtocol
    private let viewportPrefetch: LookbookImagePrefetchController
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var interestLoadGeneration = 0

    /// 페이지네이션 기준(마지막 문서)
    private var lastBrandDocument: DocumentSnapshot? = nil

    /// 중복 로드 방지
    private var didLoadInitialPage = false
    private var isLoadingInitialPage = false
    private var isLoadingNext = false

    /// 최초 로딩 시 가져올 브랜드 수
    private let initialBrandLimit: Int
    /// 첫 화면용 로고 프리패치 개수
    private let prefetchLogoCount: Int
    /// 프리패치 동시성
    private let prefetchConcurrency: Int
    /// 썸네일 다운로드 최대 바이트(목록 전용)
    private let thumbMaxBytes: Int
    private let searchLimit: Int

    init(
        repo: BrandRepositoryProtocol,
        searchUseCase: any SearchBrandsUseCaseProtocol,
        loadInterestedStyleBrandsUseCase: any LoadInterestedStyleBrandsUseCaseProtocol,
        stylePreferenceStore: CurrentUserStylePreferenceStore,
        brandAdminSessionStore: BrandAdminSessionStore,
        brandImageCache: any BrandImageCacheProtocol,
        initialBrandLimit: Int = 12,
        prefetchLogoCount: Int = 4,
        prefetchConcurrency: Int = 4,
        thumbMaxBytes: Int = 1 * 1024 * 1024,
        searchLimit: Int = 20
    ) {
        self.repo = repo
        self.searchUseCase = searchUseCase
        self.loadInterestedStyleBrandsUseCase = loadInterestedStyleBrandsUseCase
        self.stylePreferenceStore = stylePreferenceStore
        self.brandAdminSessionStore = brandAdminSessionStore
        self.brandImageCache = brandImageCache
        self.viewportPrefetch = LookbookImagePrefetchController { [brandImageCache] request in
            await brandImageCache.prefetchAssets(items: [request], concurrency: 1, storePolicy: .memoryAndDisk)
        }
        self.initialBrandLimit = initialBrandLimit
        self.prefetchLogoCount = prefetchLogoCount
        self.prefetchConcurrency = prefetchConcurrency
        self.thumbMaxBytes = thumbMaxBytes
        self.searchLimit = searchLimit
        self.canOpenAdminConsole = brandAdminSessionStore.canOpenAdminConsole
        bindBrandAdminSessionStore()
        bindSearchText()
        bindStylePreferenceStore()
    }

    /// 앱 시작 시 또는 룩북 탭 진입 전에 한 번 호출
    func loadInitialPageIfNeeded() async {
        guard !didLoadInitialPage, !isLoadingInitialPage else { return }
        let baseline = ImageCacheMetrics.shared.begin("list.home.initial")
        defer { ImageCacheMetrics.shared.end(baseline) }
        isLoadingInitialPage = true
        defer { isLoadingInitialPage = false }
        
        phase = .loading

        do {
            // 1) 브랜드 fetch (정렬 미지정: 기본 순서)
            let page = try await repo.fetchBrands(sort: nil, limit: initialBrandLimit, after: nil)
            ImageCacheMetrics.shared.mark("metadata.home.ready", parent: baseline?.id, outcome: "count_\(page.items.count)")

            // 브랜드 데이터가 준비되면 이미지를 기다리지 않고 목록을 먼저 공개한다.
            self.brands = page.items
            ImageCacheMetrics.shared.mark("list.home.published", parent: baseline?.id, outcome: "count_\(page.items.count)")
            self.lastBrandDocument = page.last
            self.phase = .ready
            didLoadInitialPage = true
            await reloadInterestedStyleBrands()
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        viewportPrefetch.clear()
        didLoadInitialPage = false
        lastBrandDocument = nil
        brands = []
        phase = .idle
        await loadInitialPageIfNeeded()
    }

    var isSearching: Bool {
        normalizedSearchText.isEmpty == false
    }

    var shouldShowInterestedStyleSection: Bool {
        interestPhase != .unconfigured
    }

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearSearch() {
        searchText = ""
    }

    func updateViewport(indices: [Int], searching: Bool) {
        let source = searching ? searchResults : brands
        let requests = indices.compactMap { index -> LookbookAssetImageRequest? in
            guard source.indices.contains(index), let path = source[index].listLogoPath,
                  !path.isEmpty else { return nil }
            return LookbookAssetImageRequest(
                primaryPath: path, secondaryPath: nil, remoteURL: nil,
                sourcePageURL: nil, maxBytes: thumbMaxBytes
            )
        }
        viewportPrefetch.update(requests)
    }

    func clearViewport() { viewportPrefetch.clear() }

    func refreshKeepingVisibleContent() async {
        guard phase == .ready else {
            await retry()
            return
        }

        guard !isLoadingInitialPage else { return }
        isLoadingInitialPage = true
        defer { isLoadingInitialPage = false }

        do {
            let page = try await repo.fetchBrands(
                sort: nil,
                limit: initialBrandLimit,
                after: nil
            )

            brands = page.items
            lastBrandDocument = page.last
            didLoadInitialPage = true
            phase = .ready
            viewportPrefetch.clear()
            await reloadInterestedStyleBrands(keepsExistingContentOnFailure: true)
        } catch {
            // 한국어 주석: 당겨서 새로고침 실패 시에는 기존 목록을 유지해 화면이 갑자기 비지 않도록 합니다.
        }
    }

    func retryInterestedStyleBrands() async {
        await reloadInterestedStyleBrands()
    }

    func reloadInterestedStyleBrands(
        keepsExistingContentOnFailure: Bool = false
    ) async {
        interestLoadGeneration += 1
        let generation = interestLoadGeneration
        let moodIDs = stylePreferenceStore.selectedMoodIDs

        guard moodIDs.isEmpty == false else {
            interestedStyleBrands = []
            interestedStyleNextCursor = nil
            interestPhase = .unconfigured
            return
        }

        interestPhase = .loading

        do {
            let page = try await loadInterestedStyleBrandsUseCase.execute(
                moodIDs: moodIDs,
                limit: 10,
                after: nil
            )
            guard generation == interestLoadGeneration else { return }

            interestedStyleBrands = page.items
            interestedStyleNextCursor = page.nextCursor
            interestPhase = page.items.isEmpty ? .empty : .ready
            schedulePrefetch(
                items: makePrefetchTargets(
                    from: page.items,
                    count: page.items.count
                )
            )
        } catch {
            guard generation == interestLoadGeneration else { return }
            if keepsExistingContentOnFailure, interestedStyleBrands.isEmpty == false {
                interestPhase = .ready
            } else {
                interestedStyleBrands = []
                interestedStyleNextCursor = nil
                interestPhase = .failed("관심 스타일 브랜드를 불러오지 못했어요")
            }
        }
    }

    /// 브랜드 생성 직후 로고 경로가 백그라운드 patch로 늦게 들어오는 경우를 보정합니다.
    /// - Note: 새 브랜드가 첫 페이지에 없더라도 홈에서 바로 보이게 하기 위해, 없으면 임시로 목록 앞에 삽입합니다.
    func syncCreatedBrand(brandID: BrandID) async {
        for attempt in 0..<6 {
            do {
                let brand = try await repo.fetchBrand(brandID: brandID)
                upsertBrand(brand)
                if await isBrandReadyForDisplay(brand) {
                    break
                }
            } catch {
                if attempt == 5 {
                    break
                }
            }

            if attempt < 5 {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    func applyUpdatedBrand(_ brand: Brand) {
        guard brand.isVisibleToUsers else {
            brands.removeAll { $0.id == brand.id }
            searchResults.removeAll { $0.id == brand.id }
            return
        }
        upsertBrand(brand)
        prefetchIfNeeded(for: brand)
    }

    /// 스크롤 바닥에서 다음 페이지 로드
    func loadNextPageIfNeeded(current brand: Brand) async {
        guard phase == .ready else { return }
        guard let last = brands.last, last.id == brand.id else { return }
        guard !isLoadingNext else { return }
        guard let after = lastBrandDocument else { return }

        isLoadingNext = true
        defer { isLoadingNext = false }

        do {
            let page = try await repo.fetchBrands(sort: nil, limit: initialBrandLimit, after: after)

            // 목록 append를 먼저 수행해서 스크롤 체감을 개선합니다.
            self.brands.append(contentsOf: page.items)
            ImageCacheMetrics.shared.mark("list.home.appended", outcome: "count_\(page.items.count)")
            self.lastBrandDocument = page.last

        } catch {
            // 페이지네이션 실패는 치명적이지 않으니 조용히 무시
        }
    }

    private func makePrefetchTargets(
        from brands: [Brand],
        count: Int
    ) -> [(path: String, maxBytes: Int)] {

        let slice = brands.prefix(max(count, 0))

        return slice.compactMap { brand in
            // 목록에서는 썸네일 -> detail -> original 순으로 폴백
            let resolved = brand.listLogoPath
            guard let path = resolved, !path.isEmpty else { return nil }

            return (path: path, maxBytes: thumbMaxBytes)
        }
    }

    private func schedulePrefetch(items: [(path: String, maxBytes: Int)]) {
        guard !items.isEmpty else { return }
        let brandImageCache = self.brandImageCache
        let concurrency = self.prefetchConcurrency
        Task(priority: .utility) {
            await brandImageCache.prefetch(items: items, concurrency: concurrency)
        }
    }

    private func upsertBrand(_ brand: Brand) {
        guard brand.isVisibleToUsers else {
            brands.removeAll { $0.id == brand.id }
            searchResults.removeAll { $0.id == brand.id }
            return
        }

        if let index = brands.firstIndex(where: { $0.id == brand.id }) {
            brands[index] = brand
            return
        }

        brands.insert(brand, at: 0)
    }

    private func prefetchIfNeeded(for brand: Brand) {
        guard let path = brand.listLogoPath else { return }
        schedulePrefetch(items: [(path: path, maxBytes: thumbMaxBytes)])
    }

    private func hasRenderableLogo(_ brand: Brand) -> Bool {
        guard let path = brand.listLogoPath else { return false }
        return path.isEmpty == false
    }

    private func isBrandReadyForDisplay(_ brand: Brand) async -> Bool {
        guard hasRenderableLogo(brand) else { return false }
        guard let path = brand.listLogoPath else { return false }

        do {
            _ = try await brandImageCache.loadImage(
                path: path,
                maxBytes: thumbMaxBytes
            )
            return true
        } catch {
            return false
        }
    }

    private func bindBrandAdminSessionStore() {
        Publishers.CombineLatest(
            brandAdminSessionStore.$isTotalAdmin,
            brandAdminSessionStore.$writableBrandIDs
        )
            .map { isTotalAdmin, writableBrandIDs in
                isTotalAdmin || writableBrandIDs.isEmpty == false
            }
            .removeDuplicates()
            .sink { [weak self] canOpenAdminConsole in
                self?.canOpenAdminConsole = canOpenAdminConsole
            }
            .store(in: &cancellables)
    }

    private func bindSearchText() {
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.scheduleSearch(query: query)
            }
            .store(in: &cancellables)
    }

    private func bindStylePreferenceStore() {
        stylePreferenceStore.$selectedMoodIDs
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.reloadInterestedStyleBrands()
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()

        guard query.isEmpty == false else {
            searchResults = []
            searchPhase = .idle
            return
        }

        searchTask = Task { [weak self] in
            await self?.performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        searchPhase = .searching

        do {
            let results = try await searchUseCase.execute(
                query: query,
                limit: searchLimit
            )
            guard !Task.isCancelled else { return }

            let visibleResults = await verifiedVisibleSearchResults(results)
            searchResults = visibleResults
            searchPhase = visibleResults.isEmpty ? .empty : .results

        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchPhase = .failed(error.localizedDescription)
        }
    }

    private func verifiedVisibleSearchResults(_ results: [Brand]) async -> [Brand] {
        var visibleResults: [Brand] = []
        visibleResults.reserveCapacity(results.count)

        for result in results where result.isVisibleToUsers {
            do {
                let brand = try await repo.fetchBrand(brandID: result.id)
                visibleResults.append(brand)
            } catch {
                continue
            }
        }

        return visibleResults
    }
}
