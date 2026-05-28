//
//  LoadLikedSeasonsUseCase.swift
//  OutPick
//
//  Created by Codex on 5/27/26.
//

import Foundation
import FirebaseFirestore

struct LikedSeasonListItem: Equatable, Identifiable {
    var id: String { "\(season.brandID.value)_\(season.id.value)" }
    let season: Season
    let userState: SeasonUserState
}

struct LikedSeasonPage {
    let items: [LikedSeasonListItem]
    let last: DocumentSnapshot?
}

protocol LoadLikedSeasonsUseCaseProtocol {
    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedSeasonPage
}

final class LoadLikedSeasonsUseCase: LoadLikedSeasonsUseCaseProtocol {
    private let seasonUserStateRepository: any SeasonUserStateRepositoryProtocol
    private let seasonRepository: any SeasonRepositoryProtocol

    init(
        seasonUserStateRepository: any SeasonUserStateRepositoryProtocol,
        seasonRepository: any SeasonRepositoryProtocol
    ) {
        self.seasonUserStateRepository = seasonUserStateRepository
        self.seasonRepository = seasonRepository
    }

    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedSeasonPage {
        let statePage = try await seasonUserStateRepository.fetchLikedSeasonUserStates(
            userID: userID,
            limit: limit,
            after: last
        )

        var items: [LikedSeasonListItem] = []
        items.reserveCapacity(statePage.items.count)

        for state in statePage.items where state.isLiked {
            do {
                let season = try await seasonRepository.fetchSeason(
                    brandID: state.brandID,
                    seasonID: state.seasonID
                )
                items.append(LikedSeasonListItem(season: season, userState: state))
            } catch {
                continue
            }
        }

        return LikedSeasonPage(items: items, last: statePage.last)
    }
}
