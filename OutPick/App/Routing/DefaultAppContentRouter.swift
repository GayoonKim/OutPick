//
//  DefaultAppContentRouter.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import UIKit

@MainActor
final class DefaultAppContentRouter: AppContentRouting {
    enum RoutingError: Error {
        case missingPresenter
        case missingRequiredID
        case missingNavigationController
        case unsupportedBuilder
    }

    private weak var tabController: MainTabBarController?
    private let lookbookContainer: LookbookContainer
    private weak var tabBuilder: (any MainTabBuilding)?

    init(
        tabController: MainTabBarController,
        lookbookContainer: LookbookContainer,
        tabBuilder: any MainTabBuilding
    ) {
        self.tabController = tabController
        self.lookbookContainer = lookbookContainer
        self.tabBuilder = tabBuilder
    }

    func openJoinedChatRoom(roomID: String) async throws {
        guard let tabController else { throw RoutingError.missingPresenter }

        await dismissVisiblePresentationIfNeeded(from: tabController)
        tabController.selectTab(1)

        guard let presenter = tabController.activeContentViewController else {
            throw RoutingError.missingPresenter
        }

        guard let tabBuilder else { throw RoutingError.unsupportedBuilder }
        try await tabBuilder.openChatRoom(roomID: roomID, from: presenter)
    }

    func openLookbookSharedContent(_ content: LookbookSharedContent) async throws {
        guard let tabController else { throw RoutingError.missingPresenter }

        await dismissVisiblePresentationIfNeeded(from: tabController)
        tabController.selectTab(2)

        let navigationController = tabController.selectedNavigationController
        guard let navigationController else {
            throw RoutingError.missingNavigationController
        }

        let coordinator = LookbookCoordinator(container: lookbookContainer)
        coordinator.attach(navigationController: navigationController)
        switch content.contentType {
        case .brand:
            let brand = try await lookbookContainer.provider.brandRepository.fetchBrand(
                brandID: BrandID(value: content.brandID)
            )
            coordinator.pushBrandDetail(brand: brand)

        case .season:
            guard let seasonID = content.seasonID else {
                throw RoutingError.missingRequiredID
            }
            coordinator.pushSeasonDetail(
                brandID: BrandID(value: content.brandID),
                seasonID: SeasonID(value: seasonID)
            )

        case .post:
            guard let seasonID = content.seasonID,
                  let postID = content.postID else {
                throw RoutingError.missingRequiredID
            }
            coordinator.pushPostDetail(
                brandID: BrandID(value: content.brandID),
                seasonID: SeasonID(value: seasonID),
                postID: PostID(value: postID)
            )
        }
    }

    func openMyBrandRequests() async throws {
        guard let tabController else { throw RoutingError.missingPresenter }

        await dismissVisiblePresentationIfNeeded(from: tabController)
        tabController.selectTab(4)

        guard let navigationController = tabController.selectedNavigationController else {
            throw RoutingError.missingNavigationController
        }

        let coordinator = LookbookCoordinator(container: lookbookContainer)
        coordinator.attach(navigationController: navigationController)
        coordinator.pushMyBrandRequests()
    }

    private func dismissVisiblePresentationIfNeeded(from tabController: MainTabBarController) async {
        if let active = tabController.activeContentViewController,
           active.presentingViewController != nil {
            await withCheckedContinuation { continuation in
                active.dismiss(animated: false) {
                    continuation.resume()
                }
            }
            return
        }

        await tabController.dismissPresentedControllerIfNeeded(animated: false)
    }
}
