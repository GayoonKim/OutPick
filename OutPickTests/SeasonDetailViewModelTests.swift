//
//  SeasonDetailViewModelTests.swift
//  OutPickTests
//
//  Created by Codex on 5/27/26.
//

import Foundation
import FirebaseFirestore
import Testing
import UIKit
@testable import OutPick

@MainActor
struct SeasonDetailViewModelTests {
    @Test func loadIfNeededPublishesSeasonUserState() async {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let season = makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 7)
        let userState = SeasonUserState(
            brandID: brandID,
            seasonID: seasonID,
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: userID,
            season: season,
            userState: userState
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.season?.id == seasonID)
        #expect(viewModel.season?.likeCount == 7)
        #expect(viewModel.seasonUserState?.isLiked == true)
    }

    @Test func toggleSeasonLikeAppliesServerResult() async {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let engagementRepository = SeasonEngagementRepositorySpy()
        engagementRepository.resultLikeCount = 8
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: userID,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 7),
            userState: nil,
            engagementRepository: engagementRepository
        )
        await viewModel.loadIfNeeded()

        await viewModel.toggleSeasonLike()

        #expect(engagementRepository.setLikeInputs == [true])
        #expect(viewModel.season?.likeCount == 8)
        #expect(viewModel.seasonUserState?.isLiked == true)
        #expect(viewModel.isMutatingLike == false)
        #expect(viewModel.engagementErrorMessage == nil)
    }

    @Test func toggleSeasonLikeFailureRestoresPreviousState() async {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let engagementRepository = SeasonEngagementRepositorySpy()
        engagementRepository.errorToThrow = NSError(domain: "SeasonEngagementRepositorySpy", code: -1)
        let userState = SeasonUserState(
            brandID: brandID,
            seasonID: seasonID,
            userID: userID,
            isLiked: false,
            updatedAt: Date()
        )
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: userID,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 7),
            userState: userState,
            engagementRepository: engagementRepository
        )
        await viewModel.loadIfNeeded()

        await viewModel.toggleSeasonLike()

        #expect(engagementRepository.setLikeInputs == [true])
        #expect(viewModel.season?.likeCount == 7)
        #expect(viewModel.seasonUserState?.isLiked == false)
        #expect(viewModel.isMutatingLike == false)
        #expect(viewModel.engagementErrorMessage == "좋아요를 반영하지 못했어요.")
    }

    @Test func initialLoadRequestsTwentyFourPostsAndPrefetchesFirstTwelveToDisk() async throws {
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let posts = (0..<24).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let useCase = LoadSeasonDetailUseCaseSpy(
            content: SeasonDetailContent(
                season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
                postsPage: PageResponse(
                    items: posts,
                    nextCursor: PageCursor(token: "page-2")
                )
            )
        )
        let imageCache = SeasonDetailBrandImageCacheSpy()
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: nil,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
            userState: nil,
            useCase: useCase,
            imageCache: imageCache
        )

        await viewModel.loadIfNeeded()
        try await waitUntil {
            await imageCache.prefetchRequests.isEmpty == false
        }

        #expect(useCase.initialPageSizes == [24])
        #expect(viewModel.posts.count == 24)
        #expect(await imageCache.prefetchRequests.first?.items.count == 12)
        #expect(await imageCache.prefetchRequests.first?.concurrency == 4)
        #expect(await imageCache.prefetchRequests.first?.storePolicy == .memoryAndDisk)
    }

    @Test func nearEndAppendsNextPageInSourceOrderWithoutDuplicatePosts() async {
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let firstPosts = (0..<24).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let secondPosts = [firstPosts[23]] + (24..<48).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let useCase = LoadSeasonDetailUseCaseSpy(
            content: SeasonDetailContent(
                season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
                postsPage: PageResponse(
                    items: firstPosts,
                    nextCursor: PageCursor(token: "page-2")
                )
            ),
            pageResults: [
                .success(PageResponse(items: secondPosts, nextCursor: nil))
            ]
        )
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: nil,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
            userState: nil,
            useCase: useCase
        )
        await viewModel.loadIfNeeded()

        await viewModel.loadMorePostsIfNeeded(currentPostID: firstPosts[11].id)
        #expect(useCase.postPageRequests.isEmpty)

        await viewModel.loadMorePostsIfNeeded(currentPostID: firstPosts[12].id)

        #expect(viewModel.posts.map(\.id.value) == (0..<48).map { "post-\($0)" })
        #expect(useCase.postPageRequests.map(\.cursor?.token) == ["page-2"])
    }

    @Test func appendedPagePrefetchesAllNewImagesBeforeTheirCardsAppear() async throws {
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let firstPosts = (0..<24).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let secondPosts = (24..<48).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let useCase = LoadSeasonDetailUseCaseSpy(
            content: SeasonDetailContent(
                season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
                postsPage: PageResponse(
                    items: firstPosts,
                    nextCursor: PageCursor(token: "page-2")
                )
            ),
            pageResults: [
                .success(PageResponse(items: secondPosts, nextCursor: nil))
            ]
        )
        let imageCache = SeasonDetailBrandImageCacheSpy()
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: nil,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
            userState: nil,
            useCase: useCase,
            imageCache: imageCache
        )
        await viewModel.loadIfNeeded()

        await viewModel.loadMorePostsIfNeeded(currentPostID: firstPosts[12].id)
        try await waitUntil {
            await imageCache.prefetchRequests.count == 2
        }

        let requests = await imageCache.prefetchRequests
        let appendedRequest = try #require(
            requests.first(where: { $0.items.count == 24 })
        )
        #expect(appendedRequest.items.count == 24)
        #expect(appendedRequest.concurrency == 4)
        #expect(appendedRequest.storePolicy == .memoryAndDisk)
        #expect(
            appendedRequest.items.map(\.path) ==
                (24..<48).map {
                    "brands/\(brandID.value)/seasons/\(seasonID.value)/\($0).jpg"
                }
        )
    }

    @Test func repeatedCardAppearancesDoNotPrefetchTheSamePathAgain() async throws {
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let posts = (0..<24).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let imageCache = SeasonDetailBrandImageCacheSpy()
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: nil,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
            userState: nil,
            useCase: LoadSeasonDetailUseCaseSpy(
                content: SeasonDetailContent(
                    season: makeSeason(
                        brandID: brandID,
                        seasonID: seasonID,
                        likeCount: 0
                    ),
                    postsPage: PageResponse(items: posts, nextCursor: nil)
                )
            ),
            imageCache: imageCache
        )
        await viewModel.loadIfNeeded()

        viewModel.postDidAppear(postID: posts[0].id)
        viewModel.postDidAppear(postID: posts[0].id)
        try await waitUntil {
            await imageCache.prefetchRequests.count == 2
        }

        let requests = await imageCache.prefetchRequests
        let paths = requests.flatMap { $0.items.map(\.path) }
        #expect(requests.map(\.concurrency) == [4, 4])
        #expect(paths.count == 24)
        #expect(Set(paths).count == 24)
    }

    @Test func concurrentNearEndAppearancesRequestTheSameCursorOnce() async throws {
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let firstPosts = (0..<24).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let useCase = LoadSeasonDetailUseCaseSpy(
            content: SeasonDetailContent(
                season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
                postsPage: PageResponse(
                    items: firstPosts,
                    nextCursor: PageCursor(token: "page-2")
                )
            ),
            pageResults: [
                .success(PageResponse(items: [], nextCursor: nil))
            ],
            pageDelayNanoseconds: 50_000_000
        )
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: nil,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
            userState: nil,
            useCase: useCase
        )
        await viewModel.loadIfNeeded()

        let firstRequest = Task {
            await viewModel.loadMorePostsIfNeeded(currentPostID: firstPosts[18].id)
        }
        try await Task.sleep(nanoseconds: 5_000_000)
        await viewModel.loadMorePostsIfNeeded(currentPostID: firstPosts[19].id)
        await firstRequest.value

        #expect(useCase.postPageRequests.count == 1)
    }

    @Test func filteredEmptyPageContinuesToTheNextCursor() async {
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let firstPosts = (0..<24).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let nextPost = makePost(index: 24, brandID: brandID, seasonID: seasonID)
        let useCase = LoadSeasonDetailUseCaseSpy(
            content: SeasonDetailContent(
                season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
                postsPage: PageResponse(
                    items: firstPosts,
                    nextCursor: PageCursor(token: "page-2")
                )
            ),
            pageResults: [
                .success(PageResponse(
                    items: [],
                    nextCursor: PageCursor(token: "page-3")
                )),
                .success(PageResponse(items: [nextPost], nextCursor: nil))
            ]
        )
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: nil,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
            userState: nil,
            useCase: useCase
        )
        await viewModel.loadIfNeeded()

        await viewModel.loadMorePostsIfNeeded(currentPostID: firstPosts[18].id)

        #expect(viewModel.posts.last?.id == nextPost.id)
        #expect(useCase.postPageRequests.map(\.cursor?.token) == ["page-2", "page-3"])
    }

    @Test func refreshDropsAnOlderLoadMoreResult() async throws {
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let firstPosts = (0..<24).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let refreshedPost = makePost(index: 100, brandID: brandID, seasonID: seasonID)
        let useCase = LoadSeasonDetailUseCaseSpy(
            content: SeasonDetailContent(
                season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
                postsPage: PageResponse(
                    items: firstPosts,
                    nextCursor: PageCursor(token: "page-2")
                )
            ),
            pageResults: [
                .success(PageResponse(
                    items: [makePost(index: 24, brandID: brandID, seasonID: seasonID)],
                    nextCursor: nil
                ))
            ],
            pageDelayNanoseconds: 50_000_000
        )
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: nil,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
            userState: nil,
            useCase: useCase
        )
        await viewModel.loadIfNeeded()

        let olderRequest = Task {
            await viewModel.loadMorePostsIfNeeded(currentPostID: firstPosts[18].id)
        }
        try await Task.sleep(nanoseconds: 5_000_000)
        useCase.content = SeasonDetailContent(
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
            postsPage: PageResponse(items: [refreshedPost], nextCursor: nil)
        )
        await viewModel.refresh()
        await olderRequest.value

        #expect(viewModel.posts.map(\.id) == [refreshedPost.id])
    }

    @Test func loadMoreFailureKeepsPostsAndCanRetry() async {
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let firstPosts = (0..<24).map {
            makePost(index: $0, brandID: brandID, seasonID: seasonID)
        }
        let nextPost = makePost(index: 24, brandID: brandID, seasonID: seasonID)
        let useCase = LoadSeasonDetailUseCaseSpy(
            content: SeasonDetailContent(
                season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
                postsPage: PageResponse(
                    items: firstPosts,
                    nextCursor: PageCursor(token: "page-2")
                )
            ),
            pageResults: [
                .failure(SeasonDetailTestError.failed),
                .success(PageResponse(items: [nextPost], nextCursor: nil))
            ]
        )
        let viewModel = makeViewModel(
            brandID: brandID,
            seasonID: seasonID,
            userID: nil,
            season: makeSeason(brandID: brandID, seasonID: seasonID, likeCount: 0),
            userState: nil,
            useCase: useCase
        )
        await viewModel.loadIfNeeded()

        await viewModel.loadMorePostsIfNeeded(currentPostID: firstPosts[18].id)
        #expect(viewModel.posts.count == 24)
        #expect(viewModel.loadMoreErrorMessage == "다음 룩을 불러오지 못했어요.")

        await viewModel.retryLoadingMorePosts()
        #expect(viewModel.posts.count == 25)
        #expect(viewModel.loadMoreErrorMessage == nil)
        #expect(useCase.postPageRequests.count == 2)
    }

    private func makeViewModel(
        brandID: BrandID,
        seasonID: SeasonID,
        userID: UserID?,
        season: Season,
        userState: SeasonUserState?,
        engagementRepository: SeasonEngagementRepositorySpy? = nil,
        useCase: (any LoadSeasonDetailUseCaseProtocol)? = nil,
        imageCache: (any BrandImageCacheProtocol)? = nil
    ) -> SeasonDetailViewModel {
        let engagementRepository = engagementRepository ?? SeasonEngagementRepositorySpy()
        let interactionStore = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            stateRetentionInterval: 60
        )
        return SeasonDetailViewModel(
            brandID: brandID,
            seasonID: seasonID,
            useCase: useCase ?? LoadSeasonDetailUseCaseStub(
                content: SeasonDetailContent(
                    season: season,
                    postsPage: PageResponse(items: [], nextCursor: nil)
                )
            ),
            seasonUserStateRepository: SeasonUserStateRepositoryStub(state: userState),
            seasonEngagementRepository: engagementRepository,
            seasonInteractionStore: interactionStore,
            brandImageCache: imageCache ?? SeasonDetailBrandImageCacheStub(),
            postInteractionStore: interactionStore,
            currentUserIDProvider: SeasonDetailCurrentUserIDProviderStub(userID: userID),
            maxBytes: 1_500_000
        )
    }

    private func makeSeason(
        brandID: BrandID,
        seasonID: SeasonID,
        likeCount: Int
    ) -> Season {
        Season(
            id: seasonID,
            brandID: brandID,
            displayTitle: "Season",
            sourceTitle: nil,
            year: 2026,
            term: .ss,
            coverPath: nil,
            coverRemoteURL: nil,
            description: "",
            tagIDs: [],
            tagConceptIDs: nil,
            status: .published,
            deletionStatus: .active,
            assetSyncStatus: .ready,
            metadataStatus: .confirmed,
            metadataConfidence: nil,
            sourceURL: nil,
            sourceImportJobID: nil,
            sourceSortIndex: nil,
            postCount: 0,
            likeCount: likeCount,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makePost(
        index: Int,
        brandID: BrandID,
        seasonID: SeasonID
    ) -> LookbookPost {
        LookbookPost(
            id: PostID(value: "post-\(index)"),
            brandID: brandID,
            seasonID: seasonID,
            authorID: nil,
            media: [
                MediaAsset(
                    type: .image,
                    remoteURL: URL(string: "https://example.com/\(index).jpg")!,
                    thumbPath: "brands/\(brandID.value)/seasons/\(seasonID.value)/\(index).jpg",
                    detailPath: nil,
                    sourcePageURL: nil
                )
            ],
            caption: nil,
            tagIDs: [],
            metrics: PostMetrics(
                likeCount: 0,
                commentCount: 0,
                replacementCount: 0,
                saveCount: 0,
                viewCount: nil
            ),
            deletionStatus: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await predicate() == false && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(await predicate())
    }
}

private struct LoadSeasonDetailUseCaseStub: LoadSeasonDetailUseCaseProtocol {
    let content: SeasonDetailContent

    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        pageSize: Int
    ) async throws -> SeasonDetailContent {
        content
    }

    func loadPosts(
        brandID: BrandID,
        seasonID: SeasonID,
        page: PageRequest
    ) async throws -> PageResponse<LookbookPost> {
        PageResponse(items: [], nextCursor: nil)
    }
}

@MainActor
private final class LoadSeasonDetailUseCaseSpy: LoadSeasonDetailUseCaseProtocol {
    var content: SeasonDetailContent
    private var pageResults: [Result<PageResponse<LookbookPost>, Error>]
    private let pageDelayNanoseconds: UInt64
    private(set) var initialPageSizes: [Int] = []
    private(set) var postPageRequests: [PageRequest] = []

    init(
        content: SeasonDetailContent,
        pageResults: [Result<PageResponse<LookbookPost>, Error>] = [],
        pageDelayNanoseconds: UInt64 = 0
    ) {
        self.content = content
        self.pageResults = pageResults
        self.pageDelayNanoseconds = pageDelayNanoseconds
    }

    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        pageSize: Int
    ) async throws -> SeasonDetailContent {
        initialPageSizes.append(pageSize)
        return content
    }

    func loadPosts(
        brandID: BrandID,
        seasonID: SeasonID,
        page: PageRequest
    ) async throws -> PageResponse<LookbookPost> {
        postPageRequests.append(page)
        if pageDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: pageDelayNanoseconds)
        }
        guard pageResults.isEmpty == false else {
            return PageResponse(items: [], nextCursor: nil)
        }
        return try pageResults.removeFirst().get()
    }
}

private enum SeasonDetailTestError: Error {
    case failed
}

private struct SeasonUserStateRepositoryStub: SeasonUserStateRepositoryProtocol {
    let state: SeasonUserState?

    func fetchSeasonUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> SeasonUserState? {
        state
    }

    func fetchLikedSeasonUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonUserStatePage {
        SeasonUserStatePage(items: state.map { [$0] } ?? [], last: nil)
    }
}

@MainActor
private final class SeasonEngagementRepositorySpy: SeasonEngagementRepositoryProtocol {
    var setLikeInputs: [Bool] = []
    var resultLikeCount: Int = 0
    var errorToThrow: Error?

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        isLiked: Bool
    ) async throws -> SeasonEngagementResult {
        setLikeInputs.append(isLiked)
        if let errorToThrow {
            throw errorToThrow
        }
        return SeasonEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            userID: UserID(value: "user-1"),
            isLiked: isLiked,
            likeCount: resultLikeCount
        )
    }
}

private struct SeasonDetailCurrentUserIDProviderStub: CurrentUserIDProviding {
    let userID: UserID?

    var currentUserID: UserID? {
        userID
    }
}

private struct SeasonDetailBrandImageCacheStub: BrandImageCacheProtocol {
    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        UIImage()
    }

    func storeImageData(_ data: Data, path: String) async throws {}

    func removeImage(path: String) async {}

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async { }
}

private actor SeasonDetailBrandImageCacheSpy: BrandImageCacheProtocol {
    struct PrefetchRequest {
        let items: [(path: String, maxBytes: Int)]
        let concurrency: Int
        let storePolicy: ImageCacheStorePolicy
    }

    private(set) var prefetchRequests: [PrefetchRequest] = []

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        UIImage()
    }

    func storeImageData(_ data: Data, path: String) async throws {}

    func removeImage(path: String) async {}

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async {
        prefetchRequests.append(
            PrefetchRequest(
                items: items,
                concurrency: concurrency,
                storePolicy: storePolicy
            )
        )
    }
}
