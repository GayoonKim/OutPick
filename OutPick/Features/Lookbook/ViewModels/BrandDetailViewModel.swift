//
//  BrandDetailViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

@MainActor
final class BrandDetailViewModel: ObservableObject {
    @Published private(set) var seasons: [Season] = []
    @Published private(set) var brandMetrics: BrandMetrics?
    @Published private(set) var brandUserState: BrandUserState?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isMutatingLike: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var engagementErrorMessage: String?

    private let initialPrefetchCount: Int
    private let lookAheadPrefetchCount: Int
    private let prefetchConcurrency: Int
    private let seasonRepository: any SeasonRepositoryProtocol
    private let brandUserStateRepository: any BrandUserStateRepositoryProtocol
    private let brandEngagementInteractionUseCase: BrandEngagementInteractionUseCase
    private let brandInteractionStore: any BrandInteractionManaging
    private let currentUserIDProvider: any CurrentUserIDProviding
    private let brandImageCache: any BrandImageCacheProtocol
    private let maxBytes: Int

    private var loadedBrandID: BrandID?
    private var loadedBrandInteractionID: BrandID?
    private var isRequesting: Bool = false
    private var prefetchedSeasonImagePaths = Set<String>()
    private var brandStateInvalidationTask: Task<Void, Never>?

    init(
        seasonRepository: any SeasonRepositoryProtocol,
        brandUserStateRepository: any BrandUserStateRepositoryProtocol,
        brandEngagementInteractionUseCase: BrandEngagementInteractionUseCase,
        brandInteractionStore: any BrandInteractionManaging,
        currentUserIDProvider: any CurrentUserIDProviding,
        brandImageCache: any BrandImageCacheProtocol,
        maxBytes: Int,
        initialPrefetchCount: Int = 12,
        lookAheadPrefetchCount: Int = 8,
        prefetchConcurrency: Int = 6
    ) {
        self.seasonRepository = seasonRepository
        self.brandUserStateRepository = brandUserStateRepository
        self.brandEngagementInteractionUseCase = brandEngagementInteractionUseCase
        self.brandInteractionStore = brandInteractionStore
        self.currentUserIDProvider = currentUserIDProvider
        self.brandImageCache = brandImageCache
        self.maxBytes = maxBytes
        self.initialPrefetchCount = initialPrefetchCount
        self.lookAheadPrefetchCount = lookAheadPrefetchCount
        self.prefetchConcurrency = prefetchConcurrency
    }

    deinit {
        brandStateInvalidationTask?.cancel()
    }

    var currentUserID: UserID? {
        currentUserIDProvider.currentUserID
    }

    func prepareBrandInteractionIfNeeded(brand: Brand) async {
        guard loadedBrandInteractionID != brand.id else { return }
        loadedBrandInteractionID = brand.id

        let userState = await fetchBrandUserStateIfPossible(
            brandID: brand.id,
            repository: brandUserStateRepository
        )
        brandInteractionStore.seedBrand(brand, userState: userState)
        bindBrandInteractionStore(brandID: brand.id)
    }

    func toggleBrandLike(brandID: BrandID) async {
        guard let userID = currentUserID else {
            engagementErrorMessage = "로그인이 필요합니다."
            return
        }

        engagementErrorMessage = nil
        let outcome = await brandEngagementInteractionUseCase.toggleLike(
            input: BrandEngagementInteractionInput(
                brandID: brandID,
                userID: userID,
                currentUserState: brandUserState,
                currentMetrics: brandMetrics
            )
        )
        engagementErrorMessage = outcome.errorMessage
    }

    func clearEngagementError() {
        engagementErrorMessage = nil
    }

    /// 최초 진입 시 중복 로드 방지
    func loadContentsIfNeeded(brandID: BrandID) async {
        if loadedBrandID == brandID, !seasons.isEmpty { return }
        await fetchAll(
            brandID: brandID,
            force: false
        )
    }

    /// 시즌 추가 후(시트 닫힘 등) 강제 새로고침
    func refreshContents(brandID: BrandID) async {
        await fetchAll(
            brandID: brandID,
            force: true
        )
    }

    private func fetchAll(
        brandID: BrandID,
        force: Bool
    ) async {
        if isRequesting { return }
        isRequesting = true
        defer { isRequesting = false }

        if !force, loadedBrandID == brandID, !seasons.isEmpty {
            return
        }

        loadedBrandID = brandID
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await seasonRepository.fetchAllSeasons(brandID: brandID)
            prefetchedSeasonImagePaths.removeAll()
            let sorted = fetched.sorted(by: Season.defaultSort)
            let initialTargets = makePrefetchTargets(
                from: sorted,
                startingAt: 0,
                count: initialPrefetchCount,
                maxBytes: maxBytes
            )
            await prefetchImmediately(
                items: initialTargets,
                brandImageCache: brandImageCache
            )
            seasons = sorted
        } catch {
            seasons = []
            errorMessage = "시즌을 불러오지 못했습니다."
            prefetchedSeasonImagePaths.removeAll()
        }
    }

    func prefetchInitialSeasonCoversIfNeeded() {
        let targets = makePrefetchTargets(startingAt: 0, count: initialPrefetchCount, maxBytes: maxBytes)
        schedulePrefetch(items: targets, brandImageCache: brandImageCache)
    }

    func seasonDidAppear(seasonID: SeasonID) {
        guard let currentIndex = seasons.firstIndex(where: { $0.id == seasonID }) else {
            return
        }

        let targets = makePrefetchTargets(
            startingAt: currentIndex + 1,
            count: lookAheadPrefetchCount,
            maxBytes: maxBytes
        )
        schedulePrefetch(items: targets, brandImageCache: brandImageCache)
    }

    private func makePrefetchTargets(
        from seasons: [Season],
        startingAt startIndex: Int,
        count: Int,
        maxBytes: Int
    ) -> [(path: String, maxBytes: Int)] {
        guard startIndex < seasons.count, count > 0 else {
            return []
        }

        let endIndex = min(seasons.count, startIndex + count)
        var targets: [(path: String, maxBytes: Int)] = []

        for season in seasons[startIndex..<endIndex] {
            guard let path = preferredPrefetchPath(for: season) else { continue }
            guard prefetchedSeasonImagePaths.contains(path) == false else { continue }

            prefetchedSeasonImagePaths.insert(path)
            targets.append((path: path, maxBytes: maxBytes))
        }

        return targets
    }

    private func makePrefetchTargets(
        startingAt startIndex: Int,
        count: Int,
        maxBytes: Int
    ) -> [(path: String, maxBytes: Int)] {
        makePrefetchTargets(
            from: seasons,
            startingAt: startIndex,
            count: count,
            maxBytes: maxBytes
        )
    }

    private func schedulePrefetch(
        items: [(path: String, maxBytes: Int)],
        brandImageCache: any BrandImageCacheProtocol
    ) {
        guard !items.isEmpty else { return }
        let concurrency = prefetchConcurrency

        Task(priority: .utility) {
            await brandImageCache.prefetch(
                items: items,
                concurrency: concurrency,
                storePolicy: .memoryOnly
            )
        }
    }

    private func prefetchImmediately(
        items: [(path: String, maxBytes: Int)],
        brandImageCache: any BrandImageCacheProtocol
    ) async {
        guard !items.isEmpty else { return }

        await brandImageCache.prefetch(
            items: items,
            concurrency: prefetchConcurrency,
            storePolicy: .memoryOnly
        )
    }

    private func preferredPrefetchPath(for season: Season) -> String? {
        let candidates = [season.coverThumbPath, season.coverPath]

        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }

        return nil
    }

    private func bindBrandInteractionStore(brandID: BrandID) {
        brandStateInvalidationTask?.cancel()
        brandStateInvalidationTask = nil

        applyCurrentBrandInteractionState(brandID: brandID)

        let brandInteractionStore = brandInteractionStore
        brandStateInvalidationTask = Task { [weak self, brandInteractionStore, brandID] in
            let stream = brandInteractionStore.brandStateInvalidationStream(for: [brandID])
            for await changedBrandID in stream {
                guard changedBrandID == brandID,
                      let state = brandInteractionStore.brandState(for: changedBrandID) else { continue }
                self?.applyBrandInteractionState(state)
            }
        }
    }

    private func applyCurrentBrandInteractionState(brandID: BrandID) {
        guard let state = brandInteractionStore.brandState(for: brandID) else { return }
        applyBrandInteractionState(state)
    }

    private func applyBrandInteractionState(_ state: BrandInteractionState) {
        brandMetrics = state.metrics
        brandUserState = state.userState
        isMutatingLike = state.isMutatingLike
    }

    private func fetchBrandUserStateIfPossible(
        brandID: BrandID,
        repository: any BrandUserStateRepositoryProtocol
    ) async -> BrandUserState? {
        guard let userID = currentUserID else { return nil }
        do {
            return try await repository.fetchBrandUserState(
                userID: userID,
                brandID: brandID
            )
        } catch {
            return nil
        }
    }
}
