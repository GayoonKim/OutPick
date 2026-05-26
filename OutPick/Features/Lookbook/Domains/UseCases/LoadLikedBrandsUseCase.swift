//
//  LoadLikedBrandsUseCase.swift
//  OutPick
//
//  Created by Codex on 5/26/26.
//

import Foundation
import FirebaseFirestore

struct LikedBrandListItem: Equatable, Identifiable {
    var id: BrandID { brand.id }
    let brand: Brand
    let userState: BrandUserState
}

struct LikedBrandPage {
    let items: [LikedBrandListItem]
    let last: DocumentSnapshot?
}

protocol LoadLikedBrandsUseCaseProtocol {
    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedBrandPage
}

final class LoadLikedBrandsUseCase: LoadLikedBrandsUseCaseProtocol {
    private let brandUserStateRepository: any BrandUserStateRepositoryProtocol
    private let brandRepository: any BrandRepositoryProtocol

    init(
        brandUserStateRepository: any BrandUserStateRepositoryProtocol,
        brandRepository: any BrandRepositoryProtocol
    ) {
        self.brandUserStateRepository = brandUserStateRepository
        self.brandRepository = brandRepository
    }

    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedBrandPage {
        let statePage = try await brandUserStateRepository.fetchLikedBrandUserStates(
            userID: userID,
            limit: limit,
            after: last
        )

        var items: [LikedBrandListItem] = []
        items.reserveCapacity(statePage.items.count)

        for state in statePage.items where state.isLiked {
            do {
                let brand = try await brandRepository.fetchBrand(brandID: state.brandID)
                items.append(LikedBrandListItem(brand: brand, userState: state))
            } catch {
                continue
            }
        }

        return LikedBrandPage(items: items, last: statePage.last)
    }
}
