//
//  DefaultAppContentRouter.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import SwiftUI
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
        let viewController: UIViewController

        switch content.contentType {
        case .brand:
            let brand = try await lookbookContainer.provider.brandRepository.fetchBrand(
                brandID: BrandID(value: content.brandID)
            )
            viewController = UIHostingController(
                rootView: coordinator.makeBrandDetailView(brand: brand)
                    .environment(\.repositoryProvider, lookbookContainer.provider)
                    .environmentObject(lookbookContainer.brandAdminSessionStore)
            )

        case .season:
            guard let seasonID = content.seasonID else {
                throw RoutingError.missingRequiredID
            }
            viewController = UIHostingController(
                rootView: lookbookContainer.makeSeasonDetailView(
                    brandID: BrandID(value: content.brandID),
                    seasonID: SeasonID(value: seasonID),
                    coordinator: coordinator
                )
                .environment(\.repositoryProvider, lookbookContainer.provider)
                .environmentObject(lookbookContainer.brandAdminSessionStore)
            )

        case .post:
            guard let seasonID = content.seasonID,
                  let postID = content.postID else {
                throw RoutingError.missingRequiredID
            }
            viewController = UIHostingController(
                rootView: lookbookContainer.makePostDetailView(
                    brandID: BrandID(value: content.brandID),
                    seasonID: SeasonID(value: seasonID),
                    postID: PostID(value: postID),
                    coordinator: coordinator
                )
                .environment(\.repositoryProvider, lookbookContainer.provider)
                .environmentObject(lookbookContainer.brandAdminSessionStore)
            )
        }

        viewController.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(viewController, animated: true)
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
