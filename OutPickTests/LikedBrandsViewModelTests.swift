//
//  LikedBrandsViewModelTests.swift
//  OutPickTests
//
//  Created by Codex on 5/26/26.
//

import Foundation
import FirebaseFirestore
import Testing
import UIKit
@testable import OutPick

struct LikedBrandsViewModelTests {
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
        let viewModel = LikedBrandsViewModel(
            useCase: useCase,
            brandInteractionStore: store,
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
        )

        await viewModel.loadInitialIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.items.map(\.id) == [brand.id])
        #expect(store.brandState(for: brand.id)?.userState?.isLiked == true)
        #expect(store.brandState(for: brand.id)?.metrics.likeCount == 7)
        #expect(useCase.requests.map(\.userID) == [userID])
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
        let viewModel = LikedBrandsViewModel(
            useCase: LoadLikedBrandsUseCaseSpy(
                pages: [
                    LikedBrandPage(
                        items: [LikedBrandListItem(brand: brand, userState: state)],
                        last: nil
                    )
                ]
            ),
            brandInteractionStore: store,
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
            viewModel.items.isEmpty
        }
        #expect(viewModel.phase == .empty)
    }

    @MainActor
    @Test func refreshForActivationReloadsAfterInitialEmptyState() async {
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
        let viewModel = LikedBrandsViewModel(
            useCase: useCase,
            brandInteractionStore: LookbookInteractionStore(
                maxPostStateCount: 10,
                maxCommentStateCount: 10,
                maxBrandStateCount: 10,
                stateRetentionInterval: 60
            ),
            currentUserIDProvider: CurrentUserIDProviderStub(userID: userID),
            brandImageCache: BrandImageCacheStub()
        )

        await viewModel.refreshForActivation()
        #expect(viewModel.phase == .empty)

        await viewModel.refreshForActivation()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.items.map(\.id) == [brand.id])
        #expect(useCase.requests.map(\.userID) == [userID, userID])
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
private final class LoadLikedBrandsUseCaseSpy: LoadLikedBrandsUseCaseProtocol {
    struct Request: Equatable {
        let userID: UserID
        let limit: Int
    }

    private var pages: [LikedBrandPage]
    private(set) var requests: [Request] = []

    init(pages: [LikedBrandPage]) {
        self.pages = pages
    }

    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedBrandPage {
        requests.append(Request(userID: userID, limit: limit))
        guard pages.isEmpty == false else {
            return LikedBrandPage(items: [], last: nil)
        }
        return pages.removeFirst()
    }
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
