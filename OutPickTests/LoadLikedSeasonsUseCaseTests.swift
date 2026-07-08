//
//  LoadLikedSeasonsUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 5/27/26.
//

import Foundation
import FirebaseFirestore
import Testing
@testable import OutPick

@MainActor
struct LoadLikedSeasonsUseCaseTests {
    @Test func executeCombinesLikedSeasonStatesWithSeasonDocuments() async throws {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let season = makeSeason(
            brandID: brandID,
            seasonID: SeasonID(value: "season-1")
        )
        let state = SeasonUserState(
            brandID: brandID,
            seasonID: season.id,
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let stateRepository = SeasonUserStateRepositoryFake(states: [state])
        let seasonRepository = SeasonRepositoryFake(seasons: [season.id: season])
        let useCase = LoadLikedSeasonsUseCase(
            seasonUserStateRepository: stateRepository,
            seasonRepository: seasonRepository
        )

        let page = try await useCase.execute(
            userID: userID,
            limit: 20,
            after: nil
        )

        #expect(page.items.map(\.id) == ["\(brandID.value)_\(season.id.value)"])
        #expect(page.items.first?.userState == state)
        #expect(stateRepository.requests.map(\.userID) == [userID])
        #expect(seasonRepository.fetchRequests.count == 1)
        #expect(seasonRepository.fetchRequests.first?.brandID == brandID)
        #expect(seasonRepository.fetchRequests.first?.seasonID == season.id)
    }

    @Test func executeSkipsMissingSeasonDocuments() async throws {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let state = SeasonUserState(
            brandID: brandID,
            seasonID: SeasonID(value: "season-missing"),
            userID: userID,
            isLiked: true,
            updatedAt: Date()
        )
        let useCase = LoadLikedSeasonsUseCase(
            seasonUserStateRepository: SeasonUserStateRepositoryFake(states: [state]),
            seasonRepository: SeasonRepositoryFake(seasons: [:])
        )

        let page = try await useCase.execute(
            userID: userID,
            limit: 20,
            after: nil
        )

        #expect(page.items.isEmpty)
    }

    private func makeSeason(
        brandID: BrandID,
        seasonID: SeasonID
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
            likeCount: 3,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

@MainActor
private final class SeasonUserStateRepositoryFake: SeasonUserStateRepositoryProtocol {
    struct Request: Equatable {
        let userID: UserID
        let limit: Int
    }

    private let states: [SeasonUserState]
    private(set) var requests: [Request] = []

    init(states: [SeasonUserState]) {
        self.states = states
    }

    func fetchSeasonUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> SeasonUserState? {
        states.first {
            $0.userID == userID &&
            $0.brandID == brandID &&
            $0.seasonID == seasonID
        }
    }

    func fetchLikedSeasonUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonUserStatePage {
        requests.append(Request(userID: userID, limit: limit))
        return SeasonUserStatePage(items: states, last: nil)
    }
}

@MainActor
private final class SeasonRepositoryFake: SeasonRepositoryProtocol {
    private let seasons: [SeasonID: Season]
    private(set) var fetchRequests: [(brandID: BrandID, seasonID: SeasonID)] = []

    init(seasons: [SeasonID: Season]) {
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
        throw NSError(domain: "SeasonRepositoryFake", code: -1)
    }

    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season {
        fetchRequests.append((brandID: brandID, seasonID: seasonID))
        guard let season = seasons[seasonID] else {
            throw NSError(domain: "SeasonRepositoryFake", code: -2)
        }
        return season
    }

    func fetchSeasons(
        brandID: BrandID,
        pageSize: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonPage {
        SeasonPage(items: Array(seasons.values), last: nil)
    }

    func fetchAllSeasons(brandID: BrandID) async throws -> [Season] {
        Array(seasons.values)
    }
}
