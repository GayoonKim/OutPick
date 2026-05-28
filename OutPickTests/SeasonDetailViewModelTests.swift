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

    private func makeViewModel(
        brandID: BrandID,
        seasonID: SeasonID,
        userID: UserID?,
        season: Season,
        userState: SeasonUserState?,
        engagementRepository: SeasonEngagementRepositorySpy? = nil
    ) -> SeasonDetailViewModel {
        let engagementRepository = engagementRepository ?? SeasonEngagementRepositorySpy()
        return SeasonDetailViewModel(
            brandID: brandID,
            seasonID: seasonID,
            useCase: LoadSeasonDetailUseCaseStub(
                content: SeasonDetailContent(season: season, posts: [])
            ),
            seasonUserStateRepository: SeasonUserStateRepositoryStub(state: userState),
            seasonEngagementRepository: engagementRepository,
            brandImageCache: SeasonDetailBrandImageCacheStub(),
            postInteractionStore: LookbookInteractionStore(
                maxPostStateCount: 10,
                maxCommentStateCount: 10,
                stateRetentionInterval: 60
            ),
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
}

private struct LoadSeasonDetailUseCaseStub: LoadSeasonDetailUseCaseProtocol {
    let content: SeasonDetailContent

    func execute(
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> SeasonDetailContent {
        content
    }
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

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async { }
}
