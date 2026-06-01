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
        let viewModel = LikedViewModel(
            likedBrandsUseCase: useCase,
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(pages: [LikedSeasonPage(items: [], last: nil)]),
            brandInteractionStore: store,
            seasonInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
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
        let viewModel = LikedViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(pages: [LikedBrandPage(items: [], last: nil)]),
            likedSeasonsUseCase: seasonUseCase,
            brandInteractionStore: store,
            seasonInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
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
        let viewModel = LikedViewModel(
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
            brandInteractionStore: store,
            seasonInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
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
        let viewModel = LikedViewModel(
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
            brandInteractionStore: store,
            seasonInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
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
        let viewModel = LikedViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(
                pages: [
                    LikedBrandPage(
                        items: [LikedBrandListItem(brand: brand, userState: state)],
                        last: nil
                    )
                ]
            ),
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(pages: [LikedSeasonPage(items: [], last: nil)]),
            brandInteractionStore: store,
            seasonInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
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
        let viewModel = LikedViewModel(
            likedBrandsUseCase: useCase,
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(pages: [LikedSeasonPage(items: [], last: nil)]),
            brandInteractionStore: store,
            seasonInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
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
        let viewModel = LikedViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCaseSpy(pages: [LikedBrandPage(items: [], last: nil)]),
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(
                pages: [
                    LikedSeasonPage(
                        items: [LikedSeasonListItem(season: season, userState: state)],
                        last: nil
                    )
                ]
            ),
            brandInteractionStore: store,
            seasonInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
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
        let viewModel = LikedViewModel(
            likedBrandsUseCase: useCase,
            likedSeasonsUseCase: LoadLikedSeasonsUseCaseSpy(
                pages: [
                    LikedSeasonPage(items: [], last: nil),
                    LikedSeasonPage(items: [], last: nil)
                ]
            ),
            brandInteractionStore: store,
            seasonInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
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
