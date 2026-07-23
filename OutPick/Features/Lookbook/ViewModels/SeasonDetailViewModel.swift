//
//  SeasonDetailViewModel.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

@MainActor
final class SeasonDetailViewModel: ObservableObject {
    @Published private(set) var season: Season?
    @Published private(set) var seasonUserState: SeasonUserState?
    @Published private(set) var posts: [LookbookPost] = []
    @Published private(set) var visibleCommentCounts: [PostID: Int] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var isMutatingLike: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadMoreErrorMessage: String?
    @Published private(set) var engagementErrorMessage: String?

    private let postPageSize: Int
    private let loadMoreThreshold: Int
    private let initialPrefetchCount: Int
    private let lookAheadPrefetchCount: Int
    private let prefetchConcurrency: Int
    private let brandID: BrandID
    private let seasonID: SeasonID
    private let useCase: any LoadSeasonDetailUseCaseProtocol
    private let seasonUserStateRepository: any SeasonUserStateRepositoryProtocol
    private let seasonEngagementRepository: any SeasonEngagementRepositoryProtocol
    private let seasonInteractionStore: any SeasonInteractionManaging
    private let brandImageCache: any BrandImageCacheProtocol
    private let postInteractionStore: any PostInteractionManaging
    private let currentUserIDProvider: any CurrentUserIDProviding
    private let maxBytes: Int

    private var loadedKey: String?
    private var isRequesting: Bool = false
    private var nextPostCursor: PageCursor?
    private var loadGeneration: UInt = 0
    private var prefetchedPostImagePaths = Set<String>()
    private var prefetchedThroughIndex: Int = -1
    private var pinnedPostKeys: Set<PostInteractionKey> = []
    private var postPinScopes: [PostInteractionKey: InteractionPinScope] = [:]
    private var postStateInvalidationTask: Task<Void, Never>?

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        useCase: any LoadSeasonDetailUseCaseProtocol,
        seasonUserStateRepository: any SeasonUserStateRepositoryProtocol,
        seasonEngagementRepository: any SeasonEngagementRepositoryProtocol,
        seasonInteractionStore: any SeasonInteractionManaging,
        brandImageCache: any BrandImageCacheProtocol,
        postInteractionStore: any PostInteractionManaging,
        currentUserIDProvider: any CurrentUserIDProviding,
        maxBytes: Int,
        postPageSize: Int = 24,
        loadMoreThreshold: Int = 12,
        initialPrefetchCount: Int = 12,
        lookAheadPrefetchCount: Int = 32,
        prefetchConcurrency: Int = 4
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.useCase = useCase
        self.seasonUserStateRepository = seasonUserStateRepository
        self.seasonEngagementRepository = seasonEngagementRepository
        self.seasonInteractionStore = seasonInteractionStore
        self.brandImageCache = brandImageCache
        self.postInteractionStore = postInteractionStore
        self.currentUserIDProvider = currentUserIDProvider
        self.maxBytes = maxBytes
        self.postPageSize = postPageSize
        self.loadMoreThreshold = loadMoreThreshold
        self.initialPrefetchCount = initialPrefetchCount
        self.lookAheadPrefetchCount = lookAheadPrefetchCount
        self.prefetchConcurrency = prefetchConcurrency
    }

    deinit {
        postStateInvalidationTask?.cancel()
    }

    func loadIfNeeded() async {
        let key = "\(brandID.value)|\(seasonID.value)"
        guard loadedKey != key else { return }
        await load()
    }

    func refresh() async {
        loadedKey = nil
        await load()
    }

    func toggleSeasonLike() async {
        guard let userID = currentUserIDProvider.currentUserID else {
            engagementErrorMessage = "로그인이 필요합니다."
            return
        }
        guard var currentSeason = season, isMutatingLike == false else { return }

        let previousSeason = currentSeason
        let previousUserState = seasonUserState
        let targetLiked = !(previousUserState?.isLiked ?? false)
        let delta = targetLiked ? 1 : -1
        let key = SeasonInteractionKey(brandID: brandID, seasonID: seasonID)

        engagementErrorMessage = nil
        isMutatingLike = true
        currentSeason.likeCount = max(0, currentSeason.likeCount + delta)
        season = currentSeason
        seasonUserState = SeasonUserState(
            brandID: brandID,
            seasonID: seasonID,
            userID: userID,
            isLiked: targetLiked,
            updatedAt: Date()
        )
        seasonInteractionStore.applyOptimisticSeasonLike(
            season: previousSeason,
            userID: userID,
            isLiked: targetLiked,
            baseLiked: previousUserState?.isLiked ?? false,
            baseLikeCount: previousSeason.likeCount
        )
        seasonInteractionStore.setSeasonLikeMutationState(
            key: key,
            isMutating: true
        )

        do {
            let result = try await seasonEngagementRepository.setLike(
                brandID: brandID,
                seasonID: seasonID,
                isLiked: targetLiked
            )
            seasonInteractionStore.applySeasonLikeResult(result)
            applySeasonEngagementResult(result)
        } catch {
            season = previousSeason
            seasonUserState = previousUserState
            seasonInteractionStore.restoreSeasonLike(
                season: previousSeason,
                userID: userID,
                isLiked: previousUserState?.isLiked ?? false,
                likeCount: previousSeason.likeCount
            )
            engagementErrorMessage = "좋아요를 반영하지 못했어요."
        }

        seasonInteractionStore.setSeasonLikeMutationState(
            key: key,
            isMutating: false
        )
        isMutatingLike = false
    }

    func clearEngagementError() {
        engagementErrorMessage = nil
    }

    private func load() async {
        if isRequesting { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        isRequesting = true
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        loadMoreErrorMessage = nil
        defer {
            isRequesting = false
            isLoading = false
        }

        do {
            let content = try await useCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                pageSize: postPageSize
            )
            guard generation == loadGeneration else { return }
            let userState = await fetchSeasonUserStateIfPossible()
            guard generation == loadGeneration else { return }
            prefetchedPostImagePaths.removeAll()
            prefetchedThroughIndex = -1
            let initialTargets = makePrefetchTargets(
                from: content.postsPage.items,
                startingAt: 0,
                count: initialPrefetchCount,
                maxBytes: maxBytes
            )
            prefetchedThroughIndex = min(
                content.postsPage.items.count - 1,
                max(initialPrefetchCount - 1, -1)
            )
            season = content.season
            seasonUserState = userState
            seasonInteractionStore.seedSeason(content.season, userState: userState)
            posts = content.postsPage.items
            nextPostCursor = content.postsPage.nextCursor
            content.postsPage.items.forEach { postInteractionStore.seedPostMetrics($0) }
            let loadedPostKeys = Set(content.postsPage.items.map(PostInteractionKey.init(post:)))
            updatePinnedPostKeys(loadedPostKeys)
            bindInteractionStore(postKeys: loadedPostKeys)
            loadedKey = "\(brandID.value)|\(seasonID.value)"
            schedulePrefetch(items: initialTargets, brandImageCache: brandImageCache)
        } catch {
            guard generation == loadGeneration else { return }
            season = nil
            seasonUserState = nil
            posts = []
            nextPostCursor = nil
            updatePinnedPostKeys([])
            bindInteractionStore(postKeys: [])
            errorMessage = unavailableMessage(for: error) ?? "시즌과 룩북 사진을 불러오지 못했습니다."
            prefetchedPostImagePaths.removeAll()
            prefetchedThroughIndex = -1
        }
    }

    private func unavailableMessage(for error: Error) -> String? {
        guard let error = error as? LookbookContentUnavailableError else {
            return nil
        }
        return error.errorDescription
    }

    private func fetchSeasonUserStateIfPossible() async -> SeasonUserState? {
        guard let userID = currentUserIDProvider.currentUserID else { return nil }
        do {
            return try await seasonUserStateRepository.fetchSeasonUserState(
                userID: userID,
                brandID: brandID,
                seasonID: seasonID
            )
        } catch {
            return nil
        }
    }

    private func applySeasonEngagementResult(_ result: SeasonEngagementResult) {
        if var currentSeason = season {
            currentSeason.likeCount = result.likeCount
            season = currentSeason
        }

        seasonUserState = SeasonUserState(
            brandID: result.brandID,
            seasonID: result.seasonID,
            userID: result.userID,
            isLiked: result.isLiked,
            updatedAt: Date()
        )
    }

    func prefetchInitialPostImagesIfNeeded() {
        let targets = makePrefetchTargets(startingAt: 0, count: initialPrefetchCount, maxBytes: maxBytes)
        schedulePrefetch(items: targets, brandImageCache: brandImageCache)
    }

    func postDidAppear(postID: PostID) {
        guard let currentIndex = posts.firstIndex(where: { $0.id == postID }) else {
            return
        }

        let requestedEndIndex = min(
            posts.count - 1,
            currentIndex + lookAheadPrefetchCount
        )
        guard requestedEndIndex > prefetchedThroughIndex else {
            return
        }

        let startIndex = max(currentIndex + 1, prefetchedThroughIndex + 1)
        guard startIndex < posts.count else {
            return
        }

        let targets = makePrefetchTargets(
            startingAt: startIndex,
            count: requestedEndIndex - startIndex + 1,
            maxBytes: maxBytes
        )
        prefetchedThroughIndex = requestedEndIndex
        schedulePrefetch(items: targets, brandImageCache: brandImageCache)
    }

    func loadMorePostsIfNeeded(currentPostID: PostID) async {
        guard shouldLoadMorePosts(currentPostID: currentPostID) else {
            return
        }
        await loadNextPostsPage()
    }

    func retryLoadingMorePosts() async {
        guard loadMoreErrorMessage != nil else { return }
        await loadNextPostsPage()
    }

    func displayCommentCount(for post: LookbookPost) -> Int {
        visibleCommentCounts[post.id] ?? post.metrics.commentCount
    }

    private func bindInteractionStore(postKeys: Set<PostInteractionKey>) {
        postStateInvalidationTask?.cancel()
        postStateInvalidationTask = nil

        guard postKeys.isEmpty == false else {
            visibleCommentCounts = [:]
            return
        }

        applyCurrentInteractionStates(for: postKeys)

        let postInteractionStore = postInteractionStore
        postStateInvalidationTask = Task { [weak self, postInteractionStore, postKeys] in
            let stream = postInteractionStore.postStateInvalidationStream(for: postKeys)
            for await key in stream {
                guard postKeys.contains(key),
                      let state = postInteractionStore.state(for: key) else { continue }
                self?.applyInteractionState(state)
            }
        }
    }

    private func updatePinnedPostKeys(_ nextPostKeys: Set<PostInteractionKey>) {
        let removedPostKeys = pinnedPostKeys.subtracting(nextPostKeys)
        let addedPostKeys = nextPostKeys.subtracting(pinnedPostKeys)

        for key in removedPostKeys {
            postPinScopes[key]?.invalidate()
            postPinScopes.removeValue(forKey: key)
        }

        for key in addedPostKeys {
            postPinScopes[key] = postInteractionStore.pinScope(postKeys: [key], commentIDs: [])
        }
        pinnedPostKeys = nextPostKeys
    }

    private func applyCurrentInteractionStates(for postKeys: Set<PostInteractionKey>) {
        let states = postKeys.compactMap { postInteractionStore.state(for: $0) }
        applyInteractionStates(states)
    }

    private func applyInteractionStates(_ states: [LookbookPostInteractionState]) {
        states.forEach { applyInteractionState($0) }
    }

    private func applyInteractionState(_ state: LookbookPostInteractionState) {
        guard posts.isEmpty == false else { return }

        if let visibleCommentCount = state.visibleCommentCount {
            visibleCommentCounts[state.postID] = visibleCommentCount
        } else {
            visibleCommentCounts.removeValue(forKey: state.postID)
        }

        posts = posts.map { post in
            guard post.id == state.postID else { return post }
            var updatedPost = post
            updatedPost.metrics = state.metrics
            return updatedPost
        }
    }

    private func makePrefetchTargets(
        from posts: [LookbookPost],
        startingAt startIndex: Int,
        count: Int,
        maxBytes: Int
    ) -> [(path: String, maxBytes: Int)] {
        guard startIndex < posts.count, count > 0 else {
            return []
        }

        let endIndex = min(posts.count, startIndex + count)
        var targets: [(path: String, maxBytes: Int)] = []

        for post in posts[startIndex..<endIndex] {
            guard let path = preferredPrefetchPath(for: post) else { continue }
            guard prefetchedPostImagePaths.contains(path) == false else { continue }

            prefetchedPostImagePaths.insert(path)
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
            from: posts,
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
                storePolicy: .memoryAndDisk
            )
        }
    }

    private func loadNextPostsPage() async {
        guard let cursor = nextPostCursor,
              isLoading == false,
              isLoadingMore == false else {
            return
        }

        let generation = loadGeneration
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoadingMore = false
            }
        }

        do {
            var requestedCursor = cursor
            var requestedCursorTokens = Set<String>()
            var appendedPosts: [LookbookPost] = []
            var appendedStartIndex: Int?

            while true {
                guard requestedCursorTokens.insert(requestedCursor.token).inserted else {
                    nextPostCursor = nil
                    break
                }
                let page = try await useCase.loadPosts(
                    brandID: brandID,
                    seasonID: seasonID,
                    page: PageRequest(size: postPageSize, cursor: requestedCursor)
                )
                guard generation == loadGeneration else { return }

                var existingPostIDs = Set(posts.map(\.id))
                appendedPosts = page.items.filter {
                    existingPostIDs.insert($0.id).inserted
                }
                if appendedPosts.isEmpty == false {
                    appendedStartIndex = posts.count
                }
                posts.append(contentsOf: appendedPosts)
                nextPostCursor = page.nextCursor

                guard appendedPosts.isEmpty,
                      let nextCursor = page.nextCursor else {
                    break
                }
                requestedCursor = nextCursor
            }

            appendedPosts.forEach { postInteractionStore.seedPostMetrics($0) }
            let loadedPostKeys = Set(posts.map(PostInteractionKey.init(post:)))
            updatePinnedPostKeys(loadedPostKeys)
            bindInteractionStore(postKeys: loadedPostKeys)

            if let appendedStartIndex {
                let targets = makePrefetchTargets(
                    startingAt: appendedStartIndex,
                    count: appendedPosts.count,
                    maxBytes: maxBytes
                )
                prefetchedThroughIndex = max(
                    prefetchedThroughIndex,
                    appendedStartIndex + appendedPosts.count - 1
                )
                schedulePrefetch(items: targets, brandImageCache: brandImageCache)
            }
        } catch {
            guard generation == loadGeneration else { return }
            loadMoreErrorMessage = "다음 룩을 불러오지 못했어요."
        }
    }

    private func shouldLoadMorePosts(currentPostID: PostID) -> Bool {
        guard nextPostCursor != nil,
              let index = posts.firstIndex(where: { $0.id == currentPostID })
        else {
            return false
        }
        return index >= max(posts.count - loadMoreThreshold, 0)
    }

    private func preferredPrefetchPath(for post: LookbookPost) -> String? {
        let candidates = [
            post.media.first?.preferredListPath,
            post.media.first?.preferredDetailPath
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }

        return nil
    }
}
