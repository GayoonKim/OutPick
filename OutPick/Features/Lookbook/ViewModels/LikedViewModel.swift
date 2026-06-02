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
    @Published private(set) var postSection = SectionState<LikedPostListItem>()
    @Published private(set) var engagementErrorMessage: String?

    var brandItems: [LikedBrandListItem] { brandSection.items }
    var seasonItems: [LikedSeasonListItem] { seasonSection.items }
    var postItems: [LikedPostListItem] { postSection.items }

    let brandImageCache: any BrandImageCacheProtocol

    private let likedBrandsUseCase: any LoadLikedBrandsUseCaseProtocol
    private let likedSeasonsUseCase: any LoadLikedSeasonsUseCaseProtocol
    private let likedPostsUseCase: any LoadLikedPostsUseCaseProtocol
    private let brandEngagementRepository: any BrandEngagementRepositoryProtocol
    private let seasonEngagementRepository: any SeasonEngagementRepositoryProtocol
    private let postEngagementRepository: any PostEngagementRepositoryProtocol
    private let brandInteractionStore: any BrandInteractionManaging
    private let seasonInteractionStore: any SeasonInteractionManaging
    private let postInteractionStore: any PostInteractionManaging
    private let currentUserIDProvider: any CurrentUserIDProviding
    private let pageSize: Int
    private let paginationThreshold: Int

    private var lastBrandDocument: DocumentSnapshot?
    private var lastSeasonDocument: DocumentSnapshot?
    private var lastPostDocument: DocumentSnapshot?
    private var initialLoadGate = AsyncLoadGate()
    private var isLoadingNextBrands = false
    private var isLoadingNextSeasons = false
    private var isLoadingNextPosts = false
    private var canLoadMoreBrands = true
    private var canLoadMoreSeasons = true
    private var canLoadMorePosts = true
    private var brandInvalidationTask: Task<Void, Never>?
    private var seasonInvalidationTask: Task<Void, Never>?
    private var postInvalidationTask: Task<Void, Never>?

    init(
        likedBrandsUseCase: any LoadLikedBrandsUseCaseProtocol,
        likedSeasonsUseCase: any LoadLikedSeasonsUseCaseProtocol,
        likedPostsUseCase: any LoadLikedPostsUseCaseProtocol,
        brandEngagementRepository: any BrandEngagementRepositoryProtocol,
        seasonEngagementRepository: any SeasonEngagementRepositoryProtocol,
        postEngagementRepository: any PostEngagementRepositoryProtocol,
        brandInteractionStore: any BrandInteractionManaging,
        seasonInteractionStore: any SeasonInteractionManaging,
        postInteractionStore: any PostInteractionManaging,
        currentUserIDProvider: any CurrentUserIDProviding,
        brandImageCache: any BrandImageCacheProtocol,
        pageSize: Int = 20,
        paginationThreshold: Int = 4
    ) {
        self.likedBrandsUseCase = likedBrandsUseCase
        self.likedSeasonsUseCase = likedSeasonsUseCase
        self.likedPostsUseCase = likedPostsUseCase
        self.brandEngagementRepository = brandEngagementRepository
        self.seasonEngagementRepository = seasonEngagementRepository
        self.postEngagementRepository = postEngagementRepository
        self.brandInteractionStore = brandInteractionStore
        self.seasonInteractionStore = seasonInteractionStore
        self.postInteractionStore = postInteractionStore
        self.currentUserIDProvider = currentUserIDProvider
        self.brandImageCache = brandImageCache
        self.pageSize = pageSize
        self.paginationThreshold = paginationThreshold
    }

    deinit {
        brandInvalidationTask?.cancel()
        seasonInvalidationTask?.cancel()
        postInvalidationTask?.cancel()
    }

    func refreshForActivation() async {
        if initialLoadGate.canUseCachedResult {
            applyStoredBrandStates()
            applyStoredSeasonStates()
            applyStoredPostStates()
            updateAggregatePhase()
        } else {
            await reload()
        }
    }

    func loadInitialIfNeeded() async {
        guard initialLoadGate.beginIfNeeded() else { return }
        var didComplete = false
        defer { initialLoadGate.finish(didComplete: didComplete) }

        didComplete = await loadLikedContent(
            showsLoading: true,
            clearsItemsOnFailure: true
        )
    }

    func reload() async {
        guard initialLoadGate.begin() else { return }
        var didComplete = false
        defer { initialLoadGate.finish(didComplete: didComplete) }

        didComplete = await loadLikedContent(
            showsLoading: true,
            clearsItemsOnFailure: true
        )
    }

    func clearEngagementError() {
        engagementErrorMessage = nil
    }

    private func loadLikedContent(
        showsLoading: Bool,
        clearsItemsOnFailure: Bool
    ) async -> Bool {
        guard let userID = currentUserIDProvider.currentUserID else {
            phase = .failed("로그인이 필요합니다.")
            brandSection = SectionState(phase: .failed("로그인이 필요합니다."), items: [])
            seasonSection = SectionState(phase: .failed("로그인이 필요합니다."), items: [])
            postSection = SectionState(phase: .failed("로그인이 필요합니다."), items: [])
            return false
        }

        if showsLoading {
            phase = .loading
            brandSection.phase = .loading
            seasonSection.phase = .loading
            postSection.phase = .loading
        }
        lastBrandDocument = nil
        lastSeasonDocument = nil
        lastPostDocument = nil
        canLoadMoreBrands = true
        canLoadMoreSeasons = true
        canLoadMorePosts = true

        async let brandPageResult = loadBrandPage(userID: userID, after: nil)
        async let seasonPageResult = loadSeasonPage(userID: userID, after: nil)
        async let postPageResult = loadPostPage(userID: userID, after: nil)
        let (brandResult, seasonResult, postResult) = await (
            brandPageResult,
            seasonPageResult,
            postPageResult
        )

        applyBrandSectionResult(brandResult, clearsItemsOnFailure: clearsItemsOnFailure)
        applySeasonSectionResult(seasonResult, clearsItemsOnFailure: clearsItemsOnFailure)
        applyPostSectionResult(postResult, clearsItemsOnFailure: clearsItemsOnFailure)
        updateAggregatePhase()
        return true
    }

    func loadNextBrandPageIfNeeded(current item: LikedBrandListItem) async {
        guard shouldLoadNextPage(currentID: item.id, items: brandSection.items.map(\.id)) else { return }
        guard brandSection.phase == .ready else { return }
        guard canLoadMoreBrands, isLoadingNextBrands == false else { return }
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
            seedBrandInteractionStore(items: page.items)
            bindBrandInteractionStore()
        } catch {
            canLoadMoreBrands = false
        }
    }

    func loadNextSeasonPageIfNeeded(current item: LikedSeasonListItem) async {
        guard shouldLoadNextPage(currentID: item.id, items: seasonSection.items.map(\.id)) else { return }
        guard seasonSection.phase == .ready else { return }
        guard canLoadMoreSeasons, isLoadingNextSeasons == false else { return }
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

    func loadNextPostPageIfNeeded(current item: LikedPostListItem) async {
        guard shouldLoadNextPage(currentID: item.id, items: postSection.items.map(\.id)) else { return }
        guard postSection.phase == .ready else { return }
        guard canLoadMorePosts, isLoadingNextPosts == false else { return }
        guard let userID = currentUserIDProvider.currentUserID else { return }
        guard let lastPostDocument else { return }

        isLoadingNextPosts = true
        defer { isLoadingNextPosts = false }

        do {
            let page = try await likedPostsUseCase.execute(
                userID: userID,
                limit: pageSize,
                after: lastPostDocument
            )
            self.lastPostDocument = page.last
            canLoadMorePosts = page.last != nil
            appendDeduplicatedPosts(page.items)
            seedPostInteractionStore(items: page.items)
            bindPostInteractionStore()
        } catch {
            canLoadMorePosts = false
        }
    }

    func unlikeBrand(_ item: LikedBrandListItem) async {
        guard let userID = currentUserIDProvider.currentUserID else {
            engagementErrorMessage = "로그인이 필요합니다."
            return
        }
        guard let removed = removeBrand(item.id) else { return }

        brandInteractionStore.applyOptimisticBrandLike(
            brandID: item.id,
            userID: userID,
            isLiked: false,
            baseLiked: item.userState.isLiked,
            baseLikeCount: item.brand.metrics.likeCount
        )

        do {
            let result = try await brandEngagementRepository.setLike(
                brandID: item.id,
                isLiked: false
            )
            brandInteractionStore.applyBrandLikeResult(result)
        } catch {
            restoreBrand(removed)
            brandInteractionStore.restoreBrandLike(
                brandID: item.id,
                userID: userID,
                isLiked: item.userState.isLiked,
                likeCount: item.brand.metrics.likeCount
            )
            engagementErrorMessage = "좋아요 취소를 반영하지 못했어요."
        }
    }

    func unlikeSeason(_ item: LikedSeasonListItem) async {
        guard let userID = currentUserIDProvider.currentUserID else {
            engagementErrorMessage = "로그인이 필요합니다."
            return
        }
        let key = SeasonInteractionKey(brandID: item.season.brandID, seasonID: item.season.id)
        guard let removed = removeSeason(item.id) else { return }

        seasonInteractionStore.applyOptimisticSeasonLike(
            season: item.season,
            userID: userID,
            isLiked: false,
            baseLiked: item.userState.isLiked,
            baseLikeCount: item.season.likeCount
        )
        seasonInteractionStore.setSeasonLikeMutationState(key: key, isMutating: true)

        do {
            let result = try await seasonEngagementRepository.setLike(
                brandID: item.season.brandID,
                seasonID: item.season.id,
                isLiked: false
            )
            seasonInteractionStore.applySeasonLikeResult(result)
        } catch {
            restoreSeason(removed)
            seasonInteractionStore.restoreSeasonLike(
                season: item.season,
                userID: userID,
                isLiked: item.userState.isLiked,
                likeCount: item.season.likeCount
            )
            engagementErrorMessage = "좋아요 취소를 반영하지 못했어요."
        }

        seasonInteractionStore.setSeasonLikeMutationState(key: key, isMutating: false)
    }

    func unlikePost(_ item: LikedPostListItem) async {
        guard let userID = currentUserIDProvider.currentUserID else {
            engagementErrorMessage = "로그인이 필요합니다."
            return
        }
        let key = PostInteractionKey(post: item.post)
        guard let removed = removePost(item.id) else { return }

        postInteractionStore.applyOptimisticLike(
            key: key,
            userID: userID,
            isLiked: false,
            baseLiked: item.userState.isLiked,
            baseLikeCount: item.post.metrics.likeCount
        )

        do {
            let result = try await postEngagementRepository.setLike(
                brandID: item.post.brandID,
                seasonID: item.post.seasonID,
                postID: item.post.id,
                isLiked: false
            )
            postInteractionStore.applyLikeResult(result, shouldApplySave: false)
        } catch {
            restorePost(removed)
            postInteractionStore.restoreLike(
                key: key,
                userID: userID,
                isLiked: item.userState.isLiked,
                likeCount: item.post.metrics.likeCount
            )
            engagementErrorMessage = "좋아요 취소를 반영하지 못했어요."
        }
    }

    private func loadBrandPage(
        userID: UserID,
        after last: DocumentSnapshot?
    ) async -> Result<LikedBrandPage, Error> {
        do {
            let page = try await likedBrandsUseCase.execute(userID: userID, limit: pageSize, after: last)
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
            let page = try await likedSeasonsUseCase.execute(userID: userID, limit: pageSize, after: last)
            return .success(page)
        } catch {
            return .failure(error)
        }
    }

    private func loadPostPage(
        userID: UserID,
        after last: DocumentSnapshot?
    ) async -> Result<LikedPostPage, Error> {
        do {
            let page = try await likedPostsUseCase.execute(userID: userID, limit: pageSize, after: last)
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
            seedBrandInteractionStore(items: page.items)
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

    private func applyPostSectionResult(
        _ result: Result<LikedPostPage, Error>,
        clearsItemsOnFailure: Bool
    ) {
        switch result {
        case .success(let page):
            postSection.items = page.items
            postSection.phase = page.items.isEmpty ? .empty : .ready
            lastPostDocument = page.last
            canLoadMorePosts = page.last != nil
            seedPostInteractionStore(items: page.items)
            bindPostInteractionStore()

        case .failure:
            canLoadMorePosts = false
            if clearsItemsOnFailure || postSection.items.isEmpty {
                postSection.items = []
                postSection.phase = .failed("좋아요한 포스트를 불러오지 못했습니다.")
            }
        }
    }

    private func updateAggregatePhase() {
        if isEmpty &&
            brandSection.phase == .empty &&
            seasonSection.phase == .empty &&
            postSection.phase == .empty {
            phase = .empty
        } else {
            phase = .ready
        }
    }

    private func appendDeduplicatedBrands(_ newItems: [LikedBrandListItem]) {
        let existingIDs = Set(brandSection.items.map(\.id))
        brandSection.items.append(contentsOf: newItems.filter { existingIDs.contains($0.id) == false })
    }

    private func appendDeduplicatedSeasons(_ newItems: [LikedSeasonListItem]) {
        let existingIDs = Set(seasonSection.items.map(\.id))
        seasonSection.items.append(contentsOf: newItems.filter { existingIDs.contains($0.id) == false })
    }

    private func appendDeduplicatedPosts(_ newItems: [LikedPostListItem]) {
        let existingIDs = Set(postSection.items.map(\.id))
        postSection.items.append(contentsOf: newItems.filter { existingIDs.contains($0.id) == false })
    }

    private func seedBrandInteractionStore(items: [LikedBrandListItem]) {
        for item in items {
            brandInteractionStore.seedBrand(item.brand, userState: item.userState)
        }
    }

    private func seedSeasonInteractionStore(items: [LikedSeasonListItem]) {
        for item in items {
            seasonInteractionStore.seedSeason(item.season, userState: item.userState)
        }
    }

    private func seedPostInteractionStore(items: [LikedPostListItem]) {
        for item in items {
            postInteractionStore.seed(
                post: item.post,
                visibleCommentCount: item.post.metrics.commentCount,
                userState: item.userState
            )
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

    private func bindPostInteractionStore() {
        postInvalidationTask?.cancel()
        postInvalidationTask = nil

        let keys = Set(postSection.items.map { PostInteractionKey(post: $0.post) })
        guard keys.isEmpty == false else { return }

        let postInteractionStore = postInteractionStore
        postInvalidationTask = Task { [weak self, postInteractionStore, keys] in
            let stream = postInteractionStore.postStateInvalidationStream(for: keys)
            for await key in stream {
                guard let state = postInteractionStore.state(for: key) else { continue }
                self?.applyPostInteractionState(state)
            }
        }
    }

    private func applyStoredBrandStates() {
        for item in brandSection.items {
            guard let state = brandInteractionStore.brandState(for: item.id) else { continue }
            applyInteractionState(state)
        }
    }

    private func applyStoredSeasonStates() {
        for item in seasonSection.items {
            let key = SeasonInteractionKey(brandID: item.season.brandID, seasonID: item.season.id)
            guard let state = seasonInteractionStore.seasonState(for: key) else { continue }
            applySeasonInteractionState(state)
        }
    }

    private func applyStoredPostStates() {
        for item in postSection.items {
            let key = PostInteractionKey(post: item.post)
            guard let state = postInteractionStore.state(for: key) else { continue }
            applyPostInteractionState(state)
        }
    }

    private func applyInteractionState(_ state: BrandInteractionState) {
        guard state.userState?.isLiked == true else {
            _ = removeBrand(state.brandID)
            return
        }

        guard let userState = state.userState else { return }
        let item = LikedBrandListItem(brand: state.brand, userState: userState)
        if let index = brandSection.items.firstIndex(where: { $0.id == state.brandID }) {
            brandSection.items[index] = item
        } else {
            brandSection.items.insert(item, at: 0)
        }
        brandSection.phase = .ready
        updateAggregatePhase()
    }

    private func applySeasonInteractionState(_ state: SeasonInteractionState) {
        let itemID = "\(state.key.brandID.value)_\(state.key.seasonID.value)"
        guard state.userState?.isLiked == true else {
            _ = removeSeason(itemID)
            return
        }

        guard let userState = state.userState else { return }
        let item = LikedSeasonListItem(season: state.season, userState: userState)
        if let index = seasonSection.items.firstIndex(where: { $0.id == itemID }) {
            seasonSection.items[index] = item
        } else {
            seasonSection.items.insert(item, at: 0)
        }
        seasonSection.phase = .ready
        updateAggregatePhase()
    }

    private func applyPostInteractionState(_ state: LookbookPostInteractionState) {
        let itemID = "\(state.key.brandID.value)_\(state.key.seasonID.value)_\(state.key.postID.value)"
        guard state.userState?.isLiked == true else {
            _ = removePost(itemID)
            return
        }

        guard let index = postSection.items.firstIndex(where: { $0.id == itemID }) else { return }
        var post = postSection.items[index].post
        post.metrics = state.metrics
        let userState = state.userState ?? postSection.items[index].userState
        postSection.items[index] = LikedPostListItem(post: post, userState: userState)
        postSection.phase = .ready
        updateAggregatePhase()
    }

    private func removeBrand(_ id: BrandID) -> (item: LikedBrandListItem, index: Int)? {
        guard let index = brandSection.items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = brandSection.items.remove(at: index)
        if brandSection.items.isEmpty {
            brandSection.phase = .empty
        }
        updateAggregatePhase()
        return (item, index)
    }

    private func restoreBrand(_ removed: (item: LikedBrandListItem, index: Int)) {
        brandSection.items.insert(removed.item, at: min(removed.index, brandSection.items.count))
        brandSection.phase = .ready
        updateAggregatePhase()
    }

    private func removeSeason(_ id: String) -> (item: LikedSeasonListItem, index: Int)? {
        guard let index = seasonSection.items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = seasonSection.items.remove(at: index)
        if seasonSection.items.isEmpty {
            seasonSection.phase = .empty
        }
        updateAggregatePhase()
        return (item, index)
    }

    private func restoreSeason(_ removed: (item: LikedSeasonListItem, index: Int)) {
        seasonSection.items.insert(removed.item, at: min(removed.index, seasonSection.items.count))
        seasonSection.phase = .ready
        updateAggregatePhase()
    }

    private func removePost(_ id: String) -> (item: LikedPostListItem, index: Int)? {
        guard let index = postSection.items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = postSection.items.remove(at: index)
        if postSection.items.isEmpty {
            postSection.phase = .empty
        }
        bindPostInteractionStore()
        updateAggregatePhase()
        return (item, index)
    }

    private func restorePost(_ removed: (item: LikedPostListItem, index: Int)) {
        postSection.items.insert(removed.item, at: min(removed.index, postSection.items.count))
        postSection.phase = .ready
        seedPostInteractionStore(items: [removed.item])
        bindPostInteractionStore()
        updateAggregatePhase()
    }

    private func shouldLoadNextPage<ID: Equatable>(
        currentID: ID,
        items: [ID]
    ) -> Bool {
        guard let index = items.firstIndex(where: { $0 == currentID }) else { return false }
        return index >= max(items.count - paginationThreshold, 0)
    }

    private var isEmpty: Bool {
        brandSection.items.isEmpty &&
            seasonSection.items.isEmpty &&
            postSection.items.isEmpty
    }
}
