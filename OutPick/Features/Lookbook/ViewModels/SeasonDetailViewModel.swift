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
    @Published private(set) var isMutatingLike: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var engagementErrorMessage: String?

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
    private var prefetchedPostImagePaths = Set<String>()
    private var prefetchedThroughIndex: Int = -1
    private var pinnedPostIDs: Set<PostID> = []
    private var postPinScopes: [PostID: InteractionPinScope] = [:]
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
        initialPrefetchCount: Int = 8,
        lookAheadPrefetchCount: Int = 20,
        prefetchConcurrency: Int = 8
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
        isRequesting = true
        isLoading = true
        errorMessage = nil
        defer {
            isRequesting = false
            isLoading = false
        }

        do {
            let content = try await useCase.execute(
                brandID: brandID,
                seasonID: seasonID
            )
            let userState = await fetchSeasonUserStateIfPossible()
            prefetchedPostImagePaths.removeAll()
            prefetchedThroughIndex = -1
            let initialTargets = makePrefetchTargets(
                from: content.posts,
                startingAt: 0,
                count: initialPrefetchCount,
                maxBytes: maxBytes
            )
            await prefetchImmediately(
                items: initialTargets,
                brandImageCache: brandImageCache
            )
            prefetchedThroughIndex = min(
                content.posts.count - 1,
                max(initialPrefetchCount - 1, -1)
            )
            season = content.season
            seasonUserState = userState
            seasonInteractionStore.seedSeason(content.season, userState: userState)
            posts = content.posts
            content.posts.forEach { postInteractionStore.seedPostMetrics($0) }
            let loadedPostIDs = Set(content.posts.map(\.id))
            updatePinnedPostIDs(loadedPostIDs)
            bindInteractionStore(postIDs: loadedPostIDs)
            loadedKey = "\(brandID.value)|\(seasonID.value)"
        } catch {
            season = nil
            seasonUserState = nil
            posts = []
            updatePinnedPostIDs([])
            bindInteractionStore(postIDs: [])
            errorMessage = "시즌과 룩북 사진을 불러오지 못했습니다."
            prefetchedPostImagePaths.removeAll()
            prefetchedThroughIndex = -1
        }
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

    func displayCommentCount(for post: LookbookPost) -> Int {
        visibleCommentCounts[post.id] ?? post.metrics.commentCount
    }

    private func bindInteractionStore(postIDs: Set<PostID>) {
        postStateInvalidationTask?.cancel()
        postStateInvalidationTask = nil

        guard postIDs.isEmpty == false else {
            visibleCommentCounts = [:]
            return
        }

        applyCurrentInteractionStates(for: postIDs)

        let postInteractionStore = postInteractionStore
        postStateInvalidationTask = Task { [weak self, postInteractionStore, postIDs] in
            let stream = postInteractionStore.postStateInvalidationStream(for: postIDs)
            for await postID in stream {
                guard postIDs.contains(postID),
                      let state = postInteractionStore.state(for: postID) else { continue }
                self?.applyInteractionState(state)
            }
        }
    }

    private func updatePinnedPostIDs(_ nextPostIDs: Set<PostID>) {
        let removedPostIDs = pinnedPostIDs.subtracting(nextPostIDs)
        let addedPostIDs = nextPostIDs.subtracting(pinnedPostIDs)

        for postID in removedPostIDs {
            postPinScopes[postID]?.invalidate()
            postPinScopes.removeValue(forKey: postID)
        }

        for postID in addedPostIDs {
            postPinScopes[postID] = postInteractionStore.pinScope(postIDs: [postID], commentIDs: [])
        }
        pinnedPostIDs = nextPostIDs
    }

    private func applyCurrentInteractionStates(for postIDs: Set<PostID>) {
        let states = postIDs.compactMap { postInteractionStore.state(for: $0) }
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
