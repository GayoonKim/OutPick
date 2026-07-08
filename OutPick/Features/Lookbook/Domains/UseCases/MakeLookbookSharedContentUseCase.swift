//
//  MakeLookbookSharedContentUseCase.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

enum LookbookShareTarget: Identifiable, Equatable {
    case brand(Brand)
    case season(Season)
    case post(LookbookPost)

    var id: String {
        switch self {
        case .brand(let brand):
            return "brand:\(brand.id.value)"
        case .season(let season):
            return "season:\(season.brandID.value):\(season.id.value)"
        case .post(let post):
            return "post:\(post.brandID.value):\(post.seasonID.value):\(post.id.value)"
        }
    }
}

protocol MakeLookbookSharedContentUseCaseProtocol {
    func execute(target: LookbookShareTarget) async throws -> LookbookSharedContent
}

final class MakeLookbookSharedContentUseCase: MakeLookbookSharedContentUseCaseProtocol {
    private let brandRepository: any BrandRepositoryProtocol
    private let seasonRepository: any SeasonRepositoryProtocol

    init(
        brandRepository: any BrandRepositoryProtocol,
        seasonRepository: any SeasonRepositoryProtocol
    ) {
        self.brandRepository = brandRepository
        self.seasonRepository = seasonRepository
    }

    func execute(target: LookbookShareTarget) async throws -> LookbookSharedContent {
        switch target {
        case .brand(let brand):
            guard brand.isVisibleToUsers else {
                throw LookbookContentUnavailableError.brandUnavailable
            }
            return makeBrandContent(brand)

        case .season(let season):
            guard season.isVisibleToUsers else {
                throw LookbookContentUnavailableError.seasonUnavailable
            }
            let brand = try await brandRepository.fetchBrand(brandID: season.brandID)
            return makeSeasonContent(season, brand: brand)

        case .post(let post):
            guard post.isVisibleToUsers else {
                throw LookbookContentUnavailableError.postUnavailable
            }
            async let brandTask = brandRepository.fetchBrand(brandID: post.brandID)
            async let seasonTask = seasonRepository.fetchSeason(
                brandID: post.brandID,
                seasonID: post.seasonID
            )
            let (brand, season) = try await (brandTask, seasonTask)
            return makePostContent(post, brand: brand, season: season)
        }
    }

    private func makeBrandContent(_ brand: Brand) -> LookbookSharedContent {
        LookbookSharedContent(
            schemaVersion: 1,
            contentType: .brand,
            brandID: brand.id.value,
            titleSnapshot: brand.name,
            subtitleSnapshot: "브랜드",
            thumbnailPathSnapshot: brand.listLogoPath
        )
    }

    private func makeSeasonContent(_ season: Season, brand: Brand) -> LookbookSharedContent {
        LookbookSharedContent(
            schemaVersion: 1,
            contentType: .season,
            brandID: season.brandID.value,
            seasonID: season.id.value,
            titleSnapshot: season.title,
            subtitleSnapshot: brand.name,
            thumbnailPathSnapshot: season.coverThumbPath ?? season.coverPath
        )
    }

    private func makePostContent(
        _ post: LookbookPost,
        brand: Brand,
        season: Season
    ) -> LookbookSharedContent {
        let thumbnailPath = post.media.first?.preferredListPath ?? post.media.first?.preferredDetailPath
        return LookbookSharedContent(
            schemaVersion: 1,
            contentType: .post,
            brandID: post.brandID.value,
            seasonID: post.seasonID.value,
            postID: post.id.value,
            titleSnapshot: "포스트",
            subtitleSnapshot: "\(brand.name) · \(season.title)",
            thumbnailPathSnapshot: thumbnailPath
        )
    }
}
