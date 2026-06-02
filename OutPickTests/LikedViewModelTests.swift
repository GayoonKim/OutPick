//
//  LikedViewModelTests.swift
//  OutPickTests
//
//  Created by Codex on 5/26/26.
//

import Foundation
import FirebaseFirestore
import Testing
import UIKit
@testable import OutPick

struct LikedViewModelTests {
    @MainActor
    @Test func loadInitialSeedsStoreAndPublishesLikedBrands() async {
        let userID = UserID(value: "user-1")
        let brand = makeBrand(id: BrandID(value: "brand-1"), likeCount: 7)
        let state = BrandUserState(
            brandID: brand.id,
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let useCase = LoadLikedBrandsUseCaseSpy(
            pages: [
                LikedBrandPage(
                    items: [LikedBrandListItem(brand: brand, userState: state)],
                    last: nil
                )
            ]
        )
        let viewModel = makeViewModel(
            likedBrandsUseCase: useCase,
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(pages: [LikedSeasonPage(items: [], last: nil)]),
            store: store,
            userID: userID
        )

        await viewModel.loadInitialIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.brandSection.phase == .ready)
        #expect(viewModel.seasonSection.phase == .empty)
        #expect(viewModel.brandItems.map(\.id) == [brand.id])
        #expect(viewModel.seasonItems.isEmpty)
        #expect(store.brandState(for: brand.id)?.userState?.isLiked == true)
        #expect(store.brandState(for: brand.id)?.brand.id == brand.id)
        #expect(store.brandState(for: brand.id)?.metrics.likeCount == 7)
        #expect(useCase.requests.map(\.userID) == [userID])
    }

    @MainActor
    @Test func loadInitialPublishesLikedSeasons() async {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let season = makeSeason(
            brandID: brandID,
            seasonID: SeasonID(value: "season-1"),
            likeCount: 5
        )
        let state = SeasonUserState(
            brandID: brandID,
            seasonID: season.id,
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let seasonUseCase = LoadLikedSeasonsUseCaseSpy(
            pages: [
                LikedSeasonPage(
                    items: [LikedSeasonListItem(season: season, userState: state)],
                    last: nil
                )
            ]
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let viewModel = makeViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(pages: [LikedBrandPage(items: [], last: nil)]),
            likedSeasonsUseCase: seasonUseCase,
            store: store,
            userID: userID
        )

        await viewModel.loadInitialIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.brandSection.phase == .empty)
        #expect(viewModel.seasonSection.phase == .ready)
        #expect(viewModel.brandItems.isEmpty)
        #expect(viewModel.seasonItems.map(\.id) == ["\(brandID.value)_\(season.id.value)"])
        let key = SeasonInteractionKey(brandID: brandID, seasonID: season.id)
        #expect(store.seasonState(for: key)?.userState?.isLiked == true)
        #expect(store.seasonState(for: key)?.season.likeCount == 5)
        #expect(seasonUseCase.requests.map(\.userID) == [userID])
    }

    @MainActor
    @Test func loadInitialPublishesLikedPosts() async {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let post = makePost(
            brandID: brandID,
            seasonID: seasonID,
            postID: PostID(value: "post-1"),
            likeCount: 3,
            commentCount: 2
        )
        let state = PostUserState(
            brandID: brandID,
            seasonID: seasonID,
            postID: post.id,
            userID: userID,
            isLiked: true,
            isSaved: false,
            updatedAt: Date(),
            likedAt: Date()
        )
        let postUseCase = LoadLikedPostsUseCaseSpy(
            pages: [
                LikedPostPage(
                    items: [LikedPostListItem(post: post, userState: state)],
                    last: nil
                )
            ]
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let viewModel = LikedViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(pages: [LikedBrandPage(items: [], last: nil)]),
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(pages: [LikedSeasonPage(items: [], last: nil)]),
            likedPostsUseCase: postUseCase,
            brandEngagementRepository: LikedBrandEngagementRepositoryStub(),
            seasonEngagementRepository: LikedSeasonEngagementRepositoryStub(),
            postEngagementRepository: LikedPostEngagementRepositoryStub(),
            brandInteractionStore: store,
            seasonInteractionStore: store,
            postInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
        )

        await viewModel.loadInitialIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.brandSection.phase == .empty)
        #expect(viewModel.seasonSection.phase == .empty)
        #expect(viewModel.postSection.phase == .ready)
        #expect(viewModel.postItems.map(\.id) == ["\(brandID.value)_\(seasonID.value)_\(post.id.value)"])
        let key = PostInteractionKey(brandID: brandID, seasonID: seasonID, postID: post.id)
        #expect(store.state(for: key)?.userState?.isLiked == true)
        #expect(store.state(for: key)?.metrics.likeCount == 3)
        #expect(store.state(for: key)?.metrics.commentCount == 2)
        #expect(postUseCase.requests.map(\.userID) == [userID])
    }

    @MainActor
    @Test func postLikeInvalidationInsertsNewPostWithoutReload() async throws {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let post = makePost(
            brandID: brandID,
            seasonID: seasonID,
            postID: PostID(value: "post-1"),
            likeCount: 3,
            commentCount: 2
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let viewModel = makeViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(pages: [LikedBrandPage(items: [], last: nil)]),
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(pages: [LikedSeasonPage(items: [], last: nil)]),
            store: store,
            userID: userID
        )
        await viewModel.loadInitialIfNeeded()
        await Task.yield()

        store.seedPostMetrics(post)
        store.applyOptimisticLike(
            key: PostInteractionKey(post: post),
            userID: userID,
            isLiked: true,
            baseLiked: false,
            baseLikeCount: 3
        )

        try await waitUntil {
            viewModel.postItems.map(\.id) == ["\(brandID.value)_\(seasonID.value)_\(post.id.value)"]
        }
        #expect(viewModel.phase == .ready)
        #expect(viewModel.postSection.phase == .ready)
        #expect(viewModel.postItems.first?.post.metrics.likeCount == 4)
        #expect(viewModel.postItems.first?.userState.isLiked == true)
    }

    @MainActor
    @Test func loadInitialKeepsBrandSectionReadyWhenSeasonFails() async {
        let userID = UserID(value: "user-1")
        let brand = makeBrand(id: BrandID(value: "brand-1"), likeCount: 7)
        let state = BrandUserState(
            brandID: brand.id,
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let viewModel = makeViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(
                pages: [
                    LikedBrandPage(
                        items: [LikedBrandListItem(brand: brand, userState: state)],
                        last: nil
                    )
                ]
            ),
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(
                results: [.failure(LikedViewModelTestError.expected)]
            ),
            store: store,
            userID: userID
        )

        await viewModel.loadInitialIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.brandSection.phase == .ready)
        #expect(viewModel.seasonSection.phase == .failed("좋아요한 시즌을 불러오지 못했습니다."))
        #expect(viewModel.brandItems.map(\.id) == [brand.id])
        #expect(viewModel.seasonItems.isEmpty)
    }

    @MainActor
    @Test func loadInitialKeepsSeasonSectionReadyWhenBrandFails() async {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let season = makeSeason(
            brandID: brandID,
            seasonID: SeasonID(value: "season-1"),
            likeCount: 5
        )
        let state = SeasonUserState(
            brandID: brandID,
            seasonID: season.id,
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let viewModel = makeViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(
                results: [.failure(LikedViewModelTestError.expected)]
            ),
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(
                pages: [
                    LikedSeasonPage(
                        items: [LikedSeasonListItem(season: season, userState: state)],
                        last: nil
                    )
                ]
            ),
            store: store,
            userID: userID
        )

        await viewModel.loadInitialIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.brandSection.phase == .failed("좋아요한 브랜드를 불러오지 못했습니다."))
        #expect(viewModel.seasonSection.phase == .ready)
        #expect(viewModel.brandItems.isEmpty)
        #expect(viewModel.seasonItems.map(\.id) == ["\(brandID.value)_\(season.id.value)"])
    }

    @MainActor
    @Test func unlikeInvalidationRemovesBrandFromList() async throws {
        let userID = UserID(value: "user-1")
        let brand = makeBrand(id: BrandID(value: "brand-1"), likeCount: 7)
        let state = BrandUserState(
            brandID: brand.id,
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let viewModel = makeViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(
                pages: [
                    LikedBrandPage(
                        items: [LikedBrandListItem(brand: brand, userState: state)],
                        last: nil
                    )
                ]
            ),
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(pages: [LikedSeasonPage(items: [], last: nil)]),
            store: store,
            userID: userID
        )
        await viewModel.loadInitialIfNeeded()
        await Task.yield()

        store.applyOptimisticBrandLike(
            brandID: brand.id,
            userID: userID,
            isLiked: false,
            baseLiked: true,
            baseLikeCount: 7
        )

        try await waitUntil {
            viewModel.brandItems.isEmpty
        }
        #expect(viewModel.phase == .empty)
        #expect(viewModel.brandSection.phase == .empty)
    }

    @MainActor
    @Test func likeInvalidationInsertsNewBrandWithoutReload() async throws {
        let userID = UserID(value: "user-1")
        let brand = makeBrand(id: BrandID(value: "brand-1"), likeCount: 7)
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let useCase = LoadLikedBrandsUseCaseSpy(
            pages: [
                LikedBrandPage(items: [], last: nil)
            ]
        )
        let viewModel = makeViewModel(
            likedBrandsUseCase: useCase,
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(pages: [LikedSeasonPage(items: [], last: nil)]),
            store: store,
            userID: userID
        )
        await viewModel.loadInitialIfNeeded()
        await Task.yield()

        store.seedBrand(brand, userState: nil)
        store.applyOptimisticBrandLike(
            brandID: brand.id,
            userID: userID,
            isLiked: true,
            baseLiked: false,
            baseLikeCount: 7
        )

        try await waitUntil {
            viewModel.brandItems.map(\.id) == [brand.id]
        }
        #expect(viewModel.phase == .ready)
        #expect(viewModel.brandSection.phase == .ready)
        #expect(viewModel.brandItems.first?.brand.metrics.likeCount == 8)
        #expect(useCase.requests.map(\.userID) == [userID])
    }

    @MainActor
    @Test func unlikeInvalidationRemovesSeasonFromList() async throws {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let season = makeSeason(
            brandID: brandID,
            seasonID: SeasonID(value: "season-1"),
            likeCount: 5
        )
        let state = SeasonUserState(
            brandID: brandID,
            seasonID: season.id,
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let viewModel = makeViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(pages: [LikedBrandPage(items: [], last: nil)]),
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(
                pages: [
                    LikedSeasonPage(
                        items: [LikedSeasonListItem(season: season, userState: state)],
                        last: nil
                    )
                ]
            ),
            store: store,
            userID: userID
        )
        await viewModel.loadInitialIfNeeded()
        await Task.yield()

        store.applyOptimisticSeasonLike(
            season: season,
            userID: userID,
            isLiked: false,
            baseLiked: true,
            baseLikeCount: 5
        )

        try await waitUntil {
            viewModel.seasonItems.isEmpty
        }
        #expect(viewModel.phase == .empty)
        #expect(viewModel.seasonSection.phase == .empty)
    }

    @MainActor
    @Test func refreshForActivationDoesNotReloadAfterInitialLoad() async {
        let userID = UserID(value: "user-1")
        let brand = makeBrand(id: BrandID(value: "brand-1"), likeCount: 7)
        let state = BrandUserState(
            brandID: brand.id,
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let useCase = LoadLikedBrandsUseCaseSpy(
            pages: [
                LikedBrandPage(items: [], last: nil),
                LikedBrandPage(
                    items: [LikedBrandListItem(brand: brand, userState: state)],
                    last: nil
                )
            ]
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        let viewModel = makeViewModel(
            likedBrandsUseCase: useCase,
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(
                pages: [
                    LikedSeasonPage(items: [], last: nil),
                    LikedSeasonPage(items: [], last: nil)
                ]
            ),
            store: store,
            userID: userID
        )

        await viewModel.refreshForActivation()
        #expect(viewModel.phase == .empty)
        #expect(viewModel.brandSection.phase == .empty)
        #expect(viewModel.seasonSection.phase == .empty)

        await viewModel.refreshForActivation()

        #expect(viewModel.phase == .empty)
        #expect(viewModel.brandSection.phase == .empty)
        #expect(viewModel.brandItems.isEmpty)
        #expect(useCase.requests.map(\.userID) == [userID])
    }

    private func makeBrand(
        id: BrandID,
        likeCount: Int
    ) -> Brand {
        Brand(
            id: id,
            name: "Brand \(id.value)",
            websiteURL: nil,
            lookbookArchiveURL: nil,
            logoThumbPath: nil,
            logoDetailPath: nil,
            logoOriginalPath: nil,
            isFeatured: false,
            discoveryStatus: .idle,
            lastDiscoveryErrorMessage: nil,
            lastDiscoveryRequestedAt: nil,
            lastDiscoveryCompletedAt: nil,
            metrics: BrandMetrics(
                likeCount: likeCount,
                viewCount: 0,
                popularScore: 0
            ),
            updatedAt: Date()
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
            displayTitle: "Season \(seasonID.value)",
            sourceTitle: nil,
            year: 2026,
            term: .ss,
            coverPath: nil,
            coverRemoteURL: nil,
            description: "",
            tagIDs: [],
            tagConceptIDs: nil,
            status: .published,
            assetSyncStatus: .ready,
            metadataStatus: .confirmed,
            metadataConfidence: nil,
            sourceURL: nil,
            sourceImportJobID: nil,
            sourceSortIndex: nil,
            postCount: 2,
            likeCount: likeCount,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makePost(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        likeCount: Int,
        commentCount: Int
    ) -> LookbookPost {
        LookbookPost(
            id: postID,
            brandID: brandID,
            seasonID: seasonID,
            authorID: UserID(value: "author-1"),
            media: [
                MediaAsset(
                    type: .image,
                    remoteURL: URL(string: "https://example.com/post.jpg")!,
                    thumbPath: nil,
                    detailPath: nil,
                    sourcePageURL: nil
                )
            ],
            caption: nil,
            tagIDs: [],
            metrics: PostMetrics(
                likeCount: likeCount,
                commentCount: commentCount,
                replacementCount: 0,
                saveCount: 0,
                viewCount: nil
            ),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @MainActor
    private func makeViewModel(
        likedBrandsUseCase: any LoadLikedBrandsUseCaseProtocol,
        likedSeasonsUseCase: any LoadLikedSeasonsUseCaseProtocol,
        likedPostsUseCase: (any LoadLikedPostsUseCaseProtocol)? = nil,
        store: LookbookInteractionStore,
        userID: UserID
    ) -> LikedViewModel {
        let likedPostsUseCase = likedPostsUseCase ?? LoadLikedPostsUseCaseSpy(
            pages: [LikedPostPage(items: [], last: nil)]
        )
        return LikedViewModel(
            likedBrandsUseCase: likedBrandsUseCase,
            likedSeasonsUseCase: likedSeasonsUseCase,
            likedPostsUseCase: likedPostsUseCase,
            brandEngagementRepository: LikedBrandEngagementRepositoryStub(),
            seasonEngagementRepository: LikedSeasonEngagementRepositoryStub(),
            postEngagementRepository: LikedPostEngagementRepositoryStub(),
            brandInteractionStore: store,
            seasonInteractionStore: store,
            postInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while predicate() == false && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(predicate())
    }
}

@MainActor
private final class LoadLikedSeasonsUseCaseSpy: LoadLikedSeasonsUseCaseProtocol {
    struct Request: Equatable {
        let userID: UserID
        let limit: Int
    }

    private var results: [Result<LikedSeasonPage, Error>]
    private(set) var requests: [Request] = []

    init(pages: [LikedSeasonPage]) {
        self.results = pages.map { .success($0) }
    }

    init(results: [Result<LikedSeasonPage, Error>]) {
        self.results = results
    }

    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedSeasonPage {
        requests.append(Request(userID: userID, limit: limit))
        guard results.isEmpty == false else {
            return LikedSeasonPage(items: [], last: nil)
        }
        return try results.removeFirst().get()
    }
}

@MainActor
private final class LoadLikedBrandsUseCaseSpy: LoadLikedBrandsUseCaseProtocol {
    struct Request: Equatable {
        let userID: UserID
        let limit: Int
    }

    private var results: [Result<LikedBrandPage, Error>]
    private(set) var requests: [Request] = []

    init(pages: [LikedBrandPage]) {
        self.results = pages.map { .success($0) }
    }

    init(results: [Result<LikedBrandPage, Error>]) {
        self.results = results
    }

    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedBrandPage {
        requests.append(Request(userID: userID, limit: limit))
        guard results.isEmpty == false else {
            return LikedBrandPage(items: [], last: nil)
        }
        return try results.removeFirst().get()
    }
}

private enum LikedViewModelTestError: Error {
    case expected
}

private struct CurrentUserIDProviderStub: CurrentUserIDProviding {
    let userID: UserID?

    var currentUserID: UserID? {
        userID
    }
}

private struct BrandImageCacheStub: BrandImageCacheProtocol {
    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        UIImage()
    }

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async { }
}

@MainActor
private final class LoadLikedPostsUseCaseSpy: LoadLikedPostsUseCaseProtocol {
    struct Request: Equatable {
        let userID: UserID
        let limit: Int
    }

    private var results: [Result<LikedPostPage, Error>]
    private(set) var requests: [Request] = []

    init(pages: [LikedPostPage]) {
        self.results = pages.map { .success($0) }
    }

    init(results: [Result<LikedPostPage, Error>]) {
        self.results = results
    }

    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedPostPage {
        requests.append(Request(userID: userID, limit: limit))
        guard results.isEmpty == false else {
            return LikedPostPage(items: [], last: nil)
        }
        return try results.removeFirst().get()
    }
}

private struct LikedBrandEngagementRepositoryStub: BrandEngagementRepositoryProtocol {
    func setLike(
        brandID: BrandID,
        isLiked: Bool
    ) async throws -> BrandEngagementResult {
        BrandEngagementResult(
            brandID: brandID,
            userID: UserID(value: "user-1"),
            isLiked: isLiked,
            likeCount: isLiked ? 1 : 0
        )
    }
}

private struct LikedSeasonEngagementRepositoryStub: SeasonEngagementRepositoryProtocol {
    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        isLiked: Bool
    ) async throws -> SeasonEngagementResult {
        SeasonEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            userID: UserID(value: "user-1"),
            isLiked: isLiked,
            likeCount: isLiked ? 1 : 0
        )
    }
}

private struct LikedPostEngagementRepositoryStub: PostEngagementRepositoryProtocol {
    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isLiked: Bool
    ) async throws -> PostEngagementResult {
        PostEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: UserID(value: "user-1"),
            isLiked: isLiked,
            isSaved: false,
            metrics: PostMetrics(
                likeCount: isLiked ? 1 : 0,
                commentCount: 0,
                replacementCount: 0,
                saveCount: 0,
                viewCount: nil
            )
        )
    }

    func setSave(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isSaved: Bool
    ) async throws -> PostEngagementResult {
        PostEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: UserID(value: "user-1"),
            isLiked: false,
            isSaved: isSaved,
            metrics: PostMetrics(
                likeCount: 0,
                commentCount: 0,
                replacementCount: 0,
                saveCount: isSaved ? 1 : 0,
                viewCount: nil
            )
        )
    }
}
