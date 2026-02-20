//
//  LookbookRouter.swift
//  OutPick
//
//  Created by Codex on 2/21/26.
//

import Foundation

enum LookbookRoute: Hashable {
    case brand(BrandID)
    case season(brandID: BrandID, seasonID: SeasonID)
    case post(brandID: BrandID, seasonID: SeasonID, postID: PostID)
}

enum LookbookSheet: Identifiable, Equatable {
    case createBrand

    var id: String {
        switch self {
        case .createBrand:
            return "createBrand"
        }
    }
}

@MainActor
final class LookbookRouter: ObservableObject {
    @Published var path: [LookbookRoute] = []
    @Published var presentedSheet: LookbookSheet?

    func pushBrand(_ brandID: BrandID) {
        path.append(.brand(brandID))
    }

    func pushSeason(brandID: BrandID, seasonID: SeasonID) {
        path.append(.season(brandID: brandID, seasonID: seasonID))
    }

    func pushPost(brandID: BrandID, seasonID: SeasonID, postID: PostID) {
        path.append(.post(brandID: brandID, seasonID: seasonID, postID: postID))
    }

    func popToRoot() {
        path.removeAll()
    }

    func present(_ sheet: LookbookSheet) {
        presentedSheet = sheet
    }

    func dismissSheet() {
        presentedSheet = nil
    }
}
