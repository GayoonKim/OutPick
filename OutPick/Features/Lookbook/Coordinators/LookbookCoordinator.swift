//
//  LookbookCoordinator.swift
//  OutPick
//
//  Created by Codex on 5/5/26.
//

import SwiftUI
import UIKit

@MainActor
final class LookbookCoordinator {
    private let container: LookbookContainer
    private weak var navigationController: UINavigationController?

    init(container: LookbookContainer) {
        self.container = container
    }

    func attach(navigationController: UINavigationController) {
        self.navigationController = navigationController
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
    }

    func pushBrandDetail(brand: Brand) {
        push(makeBrandDetailView(brand: brand))
    }

    func pushSeasonDetail(season: Season) {
        push(makeSeasonDetailView(season: season))
    }

    func pushPostDetail(post: LookbookPost) {
        push(makePostDetailView(post: post))
    }

    func pop() {
        guard let navigationController else {
            assertionFailure("LookbookCoordinator requires an attached UINavigationController.")
            return
        }
        navigationController.popViewController(animated: true)
    }

    func makeBrandDetailView(brand: Brand) -> BrandDetailView {
        container.makeBrandDetailView(
            brand: brand,
            coordinator: self
        )
    }

    func makeSeasonDetailView(season: Season) -> SeasonDetailView {
        container.makeSeasonDetailView(
            brandID: season.brandID,
            seasonID: season.id,
            coordinator: self
        )
    }

    func makeLikedView() -> LikedView {
        container.makeLikedView(coordinator: self)
    }

    func makePostDetailView(post: LookbookPost) -> PostDetailView {
        container.makePostDetailView(
            brandID: post.brandID,
            seasonID: post.seasonID,
            postID: post.id,
            coordinator: self
        )
    }

    func makeCreateBrandFlow(
        onCreatedBrand: @escaping (BrandID) -> Void
    ) -> some View {
        container.makeCreateBrandFlow(onCreatedBrand: onCreatedBrand)
    }

    func makePostCommentCoordinator() -> PostCommentCoordinator {
        PostCommentCoordinator()
    }

    func makeCommentsSheet(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentCoordinator: PostCommentCoordinator
    ) -> some View {
        container.makeCommentsSheet(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            navigationCoordinator: self,
            commentCoordinator: commentCoordinator
        )
    }

    func makeRepliesSheet(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentComment: Comment
    ) -> some View {
        container.makeRepliesSheet(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            parentComment: parentComment
        )
    }

    private func push<Content: View>(_ view: Content) {
        guard let navigationController else {
            assertionFailure("LookbookCoordinator requires an attached UINavigationController.")
            return
        }

        let hostingController = UIHostingController(
            rootView: view
                .environment(\.repositoryProvider, container.provider)
                .environmentObject(container.brandAdminSessionStore)
        )
        hostingController.hidesBottomBarWhenPushed = true
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.pushViewController(hostingController, animated: true)
    }
}
