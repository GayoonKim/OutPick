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
    private let brandRepository: any BrandRepositoryProtocol
    private let seasonRepository: any SeasonRepositoryProtocol
    private let postRepository: any PostRepositoryProtocol

    init(
        brandRepository: any BrandRepositoryProtocol,
        seasonRepository: any SeasonRepositoryProtocol,
        postRepository: any PostRepositoryProtocol
    ) {
        self.brandRepository = brandRepository
        self.seasonRepository = seasonRepository
        self.postRepository = postRepository
    }

    func execute(
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> SeasonDetailContent {
        async let brandTask = brandRepository.fetchBrand(brandID: brandID)
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

        let (_, season, posts) = try await (brandTask, seasonTask, postsTask)
        return SeasonDetailContent(
            season: season,
            posts: posts.items
        )
    }
}
