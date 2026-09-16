//
//  BrandDetailViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

@MainActor
final class BrandDetailViewModel: ObservableObject {
    @Published private(set) var brand: Brand?
    @Published private(set) var seasons: [Season] = []
    @Published private(set) var brandMetrics: BrandMetrics?
    @Published private(set) var brandUserState: BrandUserState?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isMutatingLike: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var engagementErrorMessage: String?

    private let brandRepository: any BrandRepositoryProtocol
    private let seasonRepository: any SeasonRepositoryProtocol
    private let brandUserStateRepository: any BrandUserStateRepositoryProtocol
    private let brandEngagementInteractionUseCase: BrandEngagementInteractionUseCase
    private let brandInteractionStore: any BrandInteractionManaging
    private let currentUserIDProvider: any CurrentUserIDProviding
    private let brandImageCache: any BrandImageCacheProtocol
    private let viewportPrefetch: LookbookImagePrefetchController
    private let maxBytes: Int

    private var loadedBrandID: BrandID?
    private var loadedBrandInteractionID: BrandID?
    private var isRequesting: Bool = false
    private var brandStateInvalidationTask: Task<Void, Never>?

    init(
        brandRepository: any BrandRepositoryProtocol,
        seasonRepository: any SeasonRepositoryProtocol,
        brandUserStateRepository: any BrandUserStateRepositoryProtocol,
        brandEngagementInteractionUseCase: BrandEngagementInteractionUseCase,
        brandInteractionStore: any BrandInteractionManaging,
        currentUserIDProvider: any CurrentUserIDProviding,
        brandImageCache: any BrandImageCacheProtocol,
        maxBytes: Int
    ) {
        self.brandRepository = brandRepository
        self.seasonRepository = seasonRepository
        self.brandUserStateRepository = brandUserStateRepository
        self.brandEngagementInteractionUseCase = brandEngagementInteractionUseCase
        self.brandInteractionStore = brandInteractionStore
        self.currentUserIDProvider = currentUserIDProvider
        self.brandImageCache = brandImageCache
        self.viewportPrefetch = LookbookImagePrefetchController { [brandImageCache] request in
            await brandImageCache.prefetchAssets(items: [request], concurrency: 1, storePolicy: .memoryOnly)
        }
        self.maxBytes = maxBytes
    }

    deinit {
        brandStateInvalidationTask?.cancel()
    }

    var currentUserID: UserID? {
        currentUserIDProvider.currentUserID
    }

    func prepareInitialBrandIfNeeded(_ brand: Brand) async {
        setInitialBrandIfNeeded(brand)
        await prepareBrandInteractionIfNeeded(brand: brand)
    }

    func setInitialBrandIfNeeded(_ brand: Brand) {
        if self.brand == nil { self.brand = brand }
    }

    func applyUpdatedBrand(_ brand: Brand) async {
        self.brand = brand
        loadedBrandInteractionID = nil
        await prepareBrandInteractionIfNeeded(brand: brand)
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
        let baseline = ImageCacheMetrics.shared.begin("list.brand.initial", key: brandID.value)
        defer { ImageCacheMetrics.shared.end(baseline) }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let fetchedSeasonsTask = seasonRepository.fetchAllSeasons(brandID: brandID)
            async let refreshedBrandTask = brandRepository.fetchBrand(brandID: brandID)
            let fetched = try await fetchedSeasonsTask
            ImageCacheMetrics.shared.mark("metadata.brand.ready", key: brandID.value, parent: baseline?.id, outcome: "count_\(fetched.count)")
            viewportPrefetch.clear()
            let sorted = fetched.sorted(by: Season.defaultSort)
            seasons = sorted
            ImageCacheMetrics.shared.mark("list.brand.published", key: brandID.value, parent: baseline?.id, outcome: "count_\(sorted.count)")
            let refreshedBrand = try await refreshedBrandTask
            brand = refreshedBrand
            loadedBrandInteractionID = nil
            await prepareBrandInteractionIfNeeded(brand: refreshedBrand)
        } catch {
            if error is LookbookContentUnavailableError {
                brand = nil
                seasons = []
            }
            errorMessage = unavailableMessage(for: error) ?? "브랜드와 시즌을 새로고침하지 못했습니다."
        }
    }

    private func unavailableMessage(for error: Error) -> String? {
        guard let error = error as? LookbookContentUnavailableError else {
            return nil
        }
        return error.errorDescription
    }

    func updateViewport(indices: [Int]) {
        let requests = indices.compactMap { index -> LookbookAssetImageRequest? in
            guard seasons.indices.contains(index) else { return nil }
            let season = seasons[index]
            let request = LookbookAssetImageRequest(
                primaryPath: season.coverThumbPath,
                secondaryPath: season.coverPath,
                remoteURL: season.coverRemoteURL.flatMap(URL.init(string:)),
                sourcePageURL: season.sourceURL.flatMap(URL.init(string:)), maxBytes: maxBytes
            )
            return request.storagePaths.isEmpty && request.remote == nil ? nil : request
        }
        viewportPrefetch.update(requests)
    }

    func clearViewport() { viewportPrefetch.clear() }

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
