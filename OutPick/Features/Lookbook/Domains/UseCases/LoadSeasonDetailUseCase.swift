//
//  LoadSeasonDetailUseCase.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

struct SeasonDetailContent: Equatable {
    let season: Season
    let posts: [LookbookPost]
}

protocol LoadSeasonDetailUseCaseProtocol {
    func execute(
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> SeasonDetailContent
}

final class LoadSeasonDetailUseCase: LoadSeasonDetailUseCaseProtocol {
    private let seasonRepository: any SeasonRepositoryProtocol
    private let postRepository: any PostRepositoryProtocol

    init(
        seasonRepository: any SeasonRepositoryProtocol,
        postRepository: any PostRepositoryProtocol
    ) {
        self.seasonRepository = seasonRepository
        self.postRepository = postRepository
    }

    func execute(
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> SeasonDetailContent {
        async let seasonTask = seasonRepository.fetchSeason(
            brandID: brandID,
            seasonID: seasonID
        )
        async let postsTask = postRepository.fetchPosts(
            brandID: brandID,
            seasonID: seasonID,
            sort: .newest,
            filterTagIDs: [],
            page: PageRequest(size: 60, cursor: nil)
        )

        let (season, posts) = try await (seasonTask, postsTask)
        return SeasonDetailContent(
            season: season,
            posts: posts.items
        )
    }
}
