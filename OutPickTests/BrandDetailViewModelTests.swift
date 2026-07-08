//
//  BrandDetailViewModelTests.swift
//  OutPickTests
//
//  Created by Codex on 7/9/26.
//

import Foundation
import FirebaseFirestore
import Testing
import UIKit
@testable import OutPick

@MainActor
struct BrandDetailViewModelTests {
    @Test func refreshUpdatesBrandAndSeasonsFromRepositories() async {
        let brandID = BrandID(value: "brand-1")
        let brandRepository = BrandRepositorySpy(
            brand: makeBrand(
                id: brandID,
                name: "Updated Brand",
                logoThumbPath: "brands/brand-1/logo/thumb-v2.jpg"
            )
        )
        let seasonRepository = SeasonRepositorySpy(
            seasons: [
                makeSeason(brandID: brandID, seasonID: SeasonID(value: "season-2"), sourceSortIndex: 2),
                makeSeason(brandID: brandID, seasonID: SeasonID(value: "season-1"), sourceSortIndex: 1)
            ]
        )
        let viewModel = makeViewModel(
            brandRepository: brandRepository,
            seasonRepository: seasonRepository
        )

        await viewModel.prepareInitialBrandIfNeeded(
            makeBrand(id: brandID, name: "Initial Brand", logoThumbPath: "brands/brand-1/logo/thumb-v1.jpg")
        )
        await viewModel.refreshContents(brandID: brandID)

        #expect(viewModel.brand?.name == "Updated Brand")
        #expect(viewModel.brand?.logoThumbPath == "brands/brand-1/logo/thumb-v2.jpg")
        #expect(viewModel.seasons.map(\.id.value) == ["season-1", "season-2"])
        #expect(viewModel.errorMessage == nil)
        #expect(brandRepository.fetchBrandRequests == [brandID])
        #expect(seasonRepository.fetchAllSeasonsRequests == [brandID])
    }

    @Test func refreshClearsVisibleContentWhenBrandBecomesUnavailable() async {
        let brandID = BrandID(value: "brand-1")
        let brandRepository = BrandRepositorySpy(
            brand: makeBrand(id: brandID, name: "Initial Brand"),
            errorToThrow: LookbookContentUnavailableError.brandUnavailable
        )
        let seasonRepository = SeasonRepositorySpy(
            seasons: [makeSeason(brandID: brandID, seasonID: SeasonID(value: "season-1"))]
        )
        let viewModel = makeViewModel(
            brandRepository: brandRepository,
            seasonRepository: seasonRepository
        )

        await viewModel.prepareInitialBrandIfNeeded(makeBrand(id: brandID, name: "Initial Brand"))
        await viewModel.refreshContents(brandID: brandID)

        #expect(viewModel.brand == nil)
        #expect(viewModel.seasons.isEmpty)
        #expect(viewModel.errorMessage == "이 브랜드는 더 이상 볼 수 없습니다.")
    }

    private func makeViewModel(
        brandRepository: BrandRepositorySpy,
        seasonRepository: SeasonRepositorySpy
    ) -> BrandDetailViewModel {
        let interactionStore = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            maxSeasonStateCount: 10,
            stateRetentionInterval: 60
        )
        return BrandDetailViewModel(
            brandRepository: brandRepository,
            seasonRepository: seasonRepository,
            brandUserStateRepository: BrandUserStateRepositoryStub(),
            brandEngagementInteractionUseCase: BrandEngagementInteractionUseCase(
                repository: BrandEngagementRepositoryStub(),
                brandInteractionStore: interactionStore
            ),
            brandInteractionStore: interactionStore,
            currentUserIDProvider: CurrentUserIDProviderStub(),
            brandImageCache: BrandImageCacheStub(),
            maxBytes: 1_000_000
        )
    }
}

private final class BrandRepositorySpy: BrandRepositoryProtocol {
    private let brand: Brand
    private let errorToThrow: Error?
    private(set) var fetchBrandRequests: [BrandID] = []

    init(brand: Brand, errorToThrow: Error? = nil) {
        self.brand = brand
        self.errorToThrow = errorToThrow
    }

    func fetchBrand(brandID: BrandID) async throws -> Brand {
        fetchBrandRequests.append(brandID)
        if let errorToThrow {
            throw errorToThrow
        }
        return brand
    }

    func fetchBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        BrandPage(items: [brand], last: nil)
    }

    func fetchFeaturedBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        BrandPage(items: [brand], last: nil)
    }
}

private final class SeasonRepositorySpy: SeasonRepositoryProtocol {
    private let seasons: [Season]
    private(set) var fetchAllSeasonsRequests: [BrandID] = []

    init(seasons: [Season]) {
        self.seasons = seasons
    }

    func createSeason(
        brandID: BrandID,
        year: Int,
        term: SeasonTerm,
        description: String,
        coverImageData: Data?,
        tagIDs: [TagID],
        tagConceptIDs: [String]?
    ) async throws -> Season {
        makeSeason(brandID: brandID, seasonID: SeasonID(value: "created-season"))
    }

    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season {
        makeSeason(brandID: brandID, seasonID: seasonID)
    }

    func fetchSeasons(
        brandID: BrandID,
        pageSize: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonPage {
        SeasonPage(items: seasons, last: nil)
    }

    func fetchAllSeasons(brandID: BrandID) async throws -> [Season] {
        fetchAllSeasonsRequests.append(brandID)
        return seasons
    }
}

private struct BrandUserStateRepositoryStub: BrandUserStateRepositoryProtocol {
    func fetchBrandUserState(
        userID: UserID,
        brandID: BrandID
    ) async throws -> BrandUserState? {
        nil
    }

    func fetchLikedBrandUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandUserStatePage {
        BrandUserStatePage(items: [], last: nil)
    }
}

private struct BrandEngagementRepositoryStub: BrandEngagementRepositoryProtocol {
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

private struct CurrentUserIDProviderStub: CurrentUserIDProviding {
    var currentUserID: UserID? { UserID(value: "user-1") }
}

private struct BrandImageCacheStub: BrandImageCacheProtocol {
    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        UIImage()
    }

    func storeImageData(_ data: Data, path: String) async throws {}

    func removeImage(path: String) async {}

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async {}
}

private func makeBrand(
    id: BrandID,
    name: String,
    logoThumbPath: String? = nil
) -> Brand {
    Brand(
        id: id,
        name: name,
        englishName: nil,
        websiteURL: nil,
        lookbookArchiveURL: nil,
        logoThumbPath: logoThumbPath,
        logoDetailPath: nil,
        logoOriginalPath: nil,
        isFeatured: false,
        discoveryStatus: .idle,
        lastDiscoveryErrorMessage: nil,
        lastDiscoveryRequestedAt: nil,
        lastDiscoveryCompletedAt: nil,
        metrics: BrandMetrics(likeCount: 0, viewCount: 0, popularScore: 0),
        deletionStatus: .active,
        updatedAt: Date()
    )
}

private func makeSeason(
    brandID: BrandID,
    seasonID: SeasonID,
    sourceSortIndex: Int? = nil
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
        deletionStatus: .active,
        assetSyncStatus: .ready,
        metadataStatus: .confirmed,
        metadataConfidence: nil,
        sourceURL: nil,
        sourceImportJobID: nil,
        sourceSortIndex: sourceSortIndex,
        postCount: 0,
        likeCount: 0,
        createdAt: Date(),
        updatedAt: Date()
    )
}
