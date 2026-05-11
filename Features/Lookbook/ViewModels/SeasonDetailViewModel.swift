//
//  SeasonDetailViewModel.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Combine
import Foundation

@MainActor
final class SeasonDetailViewModel: ObservableObject {
    @Published private(set) var season: Season?
    @Published private(set) var posts: [LookbookPost] = []
    @Published private(set) var visibleCommentCounts: [PostID: Int] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private let initialPrefetchCount: Int
    private let lookAheadPrefetchCount: Int
    private let prefetchConcurrency: Int
    private let brandID: BrandID
    private let seasonID: SeasonID
    private let useCase: any LoadSeasonDetailUseCaseProtocol
    private let brandImageCache: any BrandImageCacheProtocol
    private let interactionStore: LookbookInteractionStore
    private let maxBytes: Int

    private var loadedKey: String?
    private var isRequesting: Bool = false
    private var prefetchedPostImagePaths = Set<String>()
    private var prefetchedThroughIndex: Int = -1
    private var pinnedPostIDs: Set<PostID> = []
    private var postPinScopes: [PostID: InteractionPinScope] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        useCase: any LoadSeasonDetailUseCaseProtocol,
        brandImageCache: any BrandImageCacheProtocol,
        interactionStore: LookbookInteractionStore,
        maxBytes: Int,
        initialPrefetchCount: Int = 8,
        lookAheadPrefetchCount: Int = 20,
        prefetchConcurrency: Int = 8
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.useCase = useCase
        self.brandImageCache = brandImageCache
        self.interactionStore = interactionStore
        self.maxBytes = maxBytes
        self.initialPrefetchCount = initialPrefetchCount
        self.lookAheadPrefetchCount = lookAheadPrefetchCount
        self.prefetchConcurrency = prefetchConcurrency
        bindInteractionStore()
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
            posts = content.posts
            updatePinnedPostIDs(Set(content.posts.map(\.id)))
            content.posts.forEach { interactionStore.seedPostMetrics($0) }
            loadedKey = "\(brandID.value)|\(seasonID.value)"
        } catch {
            season = nil
            posts = []
            updatePinnedPostIDs([])
            errorMessage = "시즌과 룩북 사진을 불러오지 못했습니다."
            prefetchedPostImagePaths.removeAll()
            prefetchedThroughIndex = -1
        }
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

    private func bindInteractionStore() {
        interactionStore.$postStates
            .sink { [weak self] states in
                guard let self else { return }
                self.applyInteractionStates(states)
            }
            .store(in: &cancellables)
    }

    private func updatePinnedPostIDs(_ nextPostIDs: Set<PostID>) {
        let removedPostIDs = pinnedPostIDs.subtracting(nextPostIDs)
        let addedPostIDs = nextPostIDs.subtracting(pinnedPostIDs)

        for postID in removedPostIDs {
            postPinScopes[postID]?.invalidate()
            postPinScopes.removeValue(forKey: postID)
        }

        for postID in addedPostIDs {
            postPinScopes[postID] = interactionStore.pinScope(postIDs: [postID])
        }
        pinnedPostIDs = nextPostIDs
    }

    private func applyInteractionStates(_ states: [PostID: LookbookPostInteractionState]) {
        guard posts.isEmpty == false else { return }

        visibleCommentCounts = states.reduce(into: [:]) { result, item in
            guard let visibleCommentCount = item.value.visibleCommentCount else { return }
            result[item.key] = visibleCommentCount
        }

        posts = posts.map { post in
            guard let state = states[post.id] else { return post }
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
