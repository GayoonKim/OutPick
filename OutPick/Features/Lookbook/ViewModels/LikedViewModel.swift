//
//  LikedViewModel.swift
//  OutPick
//
//  Created by Codex on 5/26/26.
//

import Foundation
import FirebaseFirestore

@MainActor
final class LikedViewModel: ObservableObject {
    enum SectionPhase: Equatable {
        case idle
        case loading
        case ready
        case empty
        case failed(String)
    }

    struct SectionState<Item: Equatable>: Equatable {
        var phase: SectionPhase = .idle
        var items: [Item] = []
    }

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case empty
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var brandSection = SectionState<LikedBrandListItem>()
    @Published private(set) var seasonSection = SectionState<LikedSeasonListItem>()

    var brandItems: [LikedBrandListItem] { brandSection.items }
    var seasonItems: [LikedSeasonListItem] { seasonSection.items }

    let brandImageCache: any BrandImageCacheProtocol

    private let likedBrandsUseCase: any LoadLikedBrandsUseCaseProtocol
    private let likedSeasonsUseCase: any LoadLikedSeasonsUseCaseProtocol
    private let brandInteractionStore: any BrandInteractionManaging
    private let seasonInteractionStore: any SeasonInteractionManaging
    private let currentUserIDProvider: any CurrentUserIDProviding
    private let pageSize: Int

    private var lastBrandDocument: DocumentSnapshot?
    private var lastSeasonDocument: DocumentSnapshot?
    private var isLoadingInitial = false
    private var isLoadingNextBrands = false
    private var isLoadingNextSeasons = false
    private var canLoadMoreBrands = true
    private var canLoadMoreSeasons = true
    private var didLoadInitial = false
    private var brandInvalidationTask: Task<Void, Never>?
    private var seasonInvalidationTask: Task<Void, Never>?

    init(
        likedBrandsUseCase: any LoadLikedBrandsUseCaseProtocol,
        likedSeasonsUseCase: any LoadLikedSeasonsUseCaseProtocol,
        brandInteractionStore: any BrandInteractionManaging,
        seasonInteractionStore: any SeasonInteractionManaging,
        currentUserIDProvider: any CurrentUserIDProviding,
        brandImageCache: any BrandImageCacheProtocol,
        pageSize: Int = 20
    ) {
        self.likedBrandsUseCase = likedBrandsUseCase
        self.likedSeasonsUseCase = likedSeasonsUseCase
        self.brandInteractionStore = brandInteractionStore
        self.seasonInteractionStore = seasonInteractionStore
        self.currentUserIDProvider = currentUserIDProvider
        self.brandImageCache = brandImageCache
        self.pageSize = pageSize
    }

    deinit {
        brandInvalidationTask?.cancel()
        seasonInvalidationTask?.cancel()
    }

    func refreshForActivation() async {
        if didLoadInitial {
            applyStoredBrandStates()
            applyStoredSeasonStates()
            updateAggregatePhase()
        } else {
            await reload()
        }
    }

    func loadInitialIfNeeded() async {
        guard didLoadInitial == false else { return }
        await reload()
    }

    func reload() async {
        await loadLikedContent(showsLoading: true, clearsItemsOnFailure: true)
    }

    private func loadLikedContent(
        showsLoading: Bool,
        clearsItemsOnFailure: Bool
    ) async {
        guard isLoadingInitial == false else { return }
        guard let userID = currentUserIDProvider.currentUserID else {
            phase = .failed("로그인이 필요합니다.")
            brandSection = SectionState(
                phase: .failed("로그인이 필요합니다."),
                items: []
            )
            seasonSection = SectionState(
                phase: .failed("로그인이 필요합니다."),
                items: []
            )
            return
        }

        isLoadingInitial = true
        defer { isLoadingInitial = false }

        if showsLoading {
            phase = .loading
            brandSection.phase = .loading
            seasonSection.phase = .loading
        }
        lastBrandDocument = nil
        lastSeasonDocument = nil
        canLoadMoreBrands = true
        canLoadMoreSeasons = true

        async let brandPageResult = loadBrandPage(userID: userID, after: nil)
        async let seasonPageResult = loadSeasonPage(userID: userID, after: nil)
        let (brandResult, seasonResult) = await (brandPageResult, seasonPageResult)

        applyBrandSectionResult(
            brandResult,
            clearsItemsOnFailure: clearsItemsOnFailure
        )
        applySeasonSectionResult(
            seasonResult,
            clearsItemsOnFailure: clearsItemsOnFailure
        )
        didLoadInitial = true
        updateAggregatePhase()
    }

    func loadNextBrandPageIfNeeded(current item: LikedBrandListItem) async {
        guard brandSection.phase == .ready else { return }
        guard canLoadMoreBrands, isLoadingNextBrands == false else { return }
        guard brandSection.items.last?.id == item.id else { return }
        guard let userID = currentUserIDProvider.currentUserID else { return }
        guard let lastBrandDocument else { return }

        isLoadingNextBrands = true
        defer { isLoadingNextBrands = false }

        do {
            let page = try await likedBrandsUseCase.execute(
                userID: userID,
                limit: pageSize,
                after: lastBrandDocument
            )
            self.lastBrandDocument = page.last
            canLoadMoreBrands = page.last != nil
            appendDeduplicatedBrands(page.items)
            seedInteractionStore(items: page.items)
            bindBrandInteractionStore()
        } catch {
            canLoadMoreBrands = false
        }
    }

    func loadNextSeasonPageIfNeeded(current item: LikedSeasonListItem) async {
        guard seasonSection.phase == .ready else { return }
        guard canLoadMoreSeasons, isLoadingNextSeasons == false else { return }
        guard seasonSection.items.last?.id == item.id else { return }
        guard let userID = currentUserIDProvider.currentUserID else { return }
        guard let lastSeasonDocument else { return }

        isLoadingNextSeasons = true
        defer { isLoadingNextSeasons = false }

        do {
            let page = try await likedSeasonsUseCase.execute(
                userID: userID,
                limit: pageSize,
                after: lastSeasonDocument
            )
            self.lastSeasonDocument = page.last
            canLoadMoreSeasons = page.last != nil
            appendDeduplicatedSeasons(page.items)
            seedSeasonInteractionStore(items: page.items)
            bindSeasonInteractionStore()
        } catch {
            canLoadMoreSeasons = false
        }
    }

    private func loadBrandPage(
        userID: UserID,
        after last: DocumentSnapshot?
    ) async -> Result<LikedBrandPage, Error> {
        do {
            let page = try await likedBrandsUseCase.execute(
                userID: userID,
                limit: pageSize,
                after: last
            )
            return .success(page)
        } catch {
            return .failure(error)
        }
    }

    private func loadSeasonPage(
        userID: UserID,
        after last: DocumentSnapshot?
    ) async -> Result<LikedSeasonPage, Error> {
        do {
            let page = try await likedSeasonsUseCase.execute(
                userID: userID,
                limit: pageSize,
                after: last
            )
            return .success(page)
        } catch {
            return .failure(error)
        }
    }

    private func applyBrandSectionResult(
        _ result: Result<LikedBrandPage, Error>,
        clearsItemsOnFailure: Bool
    ) {
        switch result {
        case .success(let page):
            brandSection.items = page.items
            brandSection.phase = page.items.isEmpty ? .empty : .ready
            lastBrandDocument = page.last
            canLoadMoreBrands = page.last != nil
            seedInteractionStore(items: page.items)
            bindBrandInteractionStore()

        case .failure:
            canLoadMoreBrands = false
            if clearsItemsOnFailure || brandSection.items.isEmpty {
                brandSection.items = []
                brandSection.phase = .failed("좋아요한 브랜드를 불러오지 못했습니다.")
                bindBrandInteractionStore()
            }
        }
    }

    private func applySeasonSectionResult(
        _ result: Result<LikedSeasonPage, Error>,
        clearsItemsOnFailure: Bool
    ) {
        switch result {
        case .success(let page):
            seasonSection.items = page.items
            seasonSection.phase = page.items.isEmpty ? .empty : .ready
            lastSeasonDocument = page.last
            canLoadMoreSeasons = page.last != nil
            seedSeasonInteractionStore(items: page.items)
            bindSeasonInteractionStore()

        case .failure:
            canLoadMoreSeasons = false
            if clearsItemsOnFailure || seasonSection.items.isEmpty {
                seasonSection.items = []
                seasonSection.phase = .failed("좋아요한 시즌을 불러오지 못했습니다.")
            }
        }
    }

    private func updateAggregatePhase() {
        if isEmpty && brandSection.phase == .empty && seasonSection.phase == .empty {
            phase = .empty
        } else {
            phase = .ready
        }
    }

    private func appendDeduplicatedBrands(_ newItems: [LikedBrandListItem]) {
        let existingIDs = Set(brandSection.items.map(\.id))
        let deduplicatedItems = newItems.filter { existingIDs.contains($0.id) == false }
        brandSection.items.append(contentsOf: deduplicatedItems)
    }

    private func appendDeduplicatedSeasons(_ newItems: [LikedSeasonListItem]) {
        let existingIDs = Set(seasonSection.items.map(\.id))
        let deduplicatedItems = newItems.filter { existingIDs.contains($0.id) == false }
        seasonSection.items.append(contentsOf: deduplicatedItems)
    }

    private func seedSeasonInteractionStore(items: [LikedSeasonListItem]) {
        for item in items {
            seasonInteractionStore.seedSeason(item.season, userState: item.userState)
        }
    }

    private func bindSeasonInteractionStore() {
        guard seasonInvalidationTask == nil else { return }

        let seasonInteractionStore = seasonInteractionStore
        seasonInvalidationTask = Task { [weak self, seasonInteractionStore] in
            let stream = seasonInteractionStore.allSeasonStateInvalidationStream()
            for await key in stream {
                guard let state = seasonInteractionStore.seasonState(for: key) else { continue }
                self?.applySeasonInteractionState(state)
            }
        }
    }

    private func applyStoredSeasonStates() {
        for item in seasonSection.items {
            let key = SeasonInteractionKey(
                brandID: item.season.brandID,
                seasonID: item.season.id
            )
            guard let state = seasonInteractionStore.seasonState(for: key) else { continue }
            applySeasonInteractionState(state)
        }
    }

    private func seedInteractionStore(items: [LikedBrandListItem]) {
        for item in items {
            brandInteractionStore.seedBrand(item.brand, userState: item.userState)
        }
    }

    private func bindBrandInteractionStore() {
        guard brandInvalidationTask == nil else { return }

        let brandInteractionStore = brandInteractionStore
        brandInvalidationTask = Task { [weak self, brandInteractionStore] in
            let stream = brandInteractionStore.allBrandStateInvalidationStream()
            for await brandID in stream {
                guard let state = brandInteractionStore.brandState(for: brandID) else { continue }
                self?.applyInteractionState(state)
            }
        }
    }

    private func applyInteractionState(_ state: BrandInteractionState) {
        guard state.userState?.isLiked == true else {
            guard let index = brandSection.items.firstIndex(where: { $0.id == state.brandID }) else { return }
            brandSection.items.remove(at: index)
            if brandSection.items.isEmpty {
                brandSection.phase = .empty
            }
            updateAggregatePhase()
            return
        }

        guard let userState = state.userState else { return }
        let item = LikedBrandListItem(
            brand: state.brand,
            userState: userState
        )
        if let index = brandSection.items.firstIndex(where: { $0.id == state.brandID }) {
            brandSection.items[index] = item
        } else {
            brandSection.items.insert(item, at: 0)
        }
        brandSection.phase = .ready
        updateAggregatePhase()
    }

    private func applyStoredBrandStates() {
        for item in brandSection.items {
            guard let state = brandInteractionStore.brandState(for: item.id) else { continue }
            applyInteractionState(state)
        }
    }

    private func applySeasonInteractionState(_ state: SeasonInteractionState) {
        let isLiked = state.userState?.isLiked == true
        let itemID = "\(state.key.brandID.value)_\(state.key.seasonID.value)"

        if isLiked {
            guard let userState = state.userState else { return }
            let item = LikedSeasonListItem(
                season: state.season,
                userState: userState
            )
            if let index = seasonSection.items.firstIndex(where: { $0.id == itemID }) {
                seasonSection.items[index] = item
            } else {
                seasonSection.items.insert(item, at: 0)
            }
            seasonSection.phase = .ready
        } else if let index = seasonSection.items.firstIndex(where: { $0.id == itemID }) {
            seasonSection.items.remove(at: index)
            if seasonSection.items.isEmpty {
                seasonSection.phase = .empty
            }
        }

        updateAggregatePhase()
    }

    private var isEmpty: Bool {
        brandSection.items.isEmpty && seasonSection.items.isEmpty
    }
}
