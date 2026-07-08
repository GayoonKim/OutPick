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

    func pushBrandRequest(initialBrandName: String) {
        push(makeBrandRequestView(
            initialBrandName: initialBrandName,
            onSubmitted: { [weak self] in
                self?.replaceTopWithMyBrandRequests(initialScope: .active)
            }
        ))
    }

    func pushBrandRequestFromRequestSituation(initialBrandName: String) {
        push(makeBrandRequestView(
            initialBrandName: initialBrandName,
            onSubmitted: { [weak self] in
                self?.pop()
            }
        ))
    }

    func pushMyBrandRequests(initialScope: BrandRequestListScope = .active) {
        push(makeMyBrandRequestsView(initialScope: initialScope))
    }

    func pushAdminHome(onCreatedBrand: @escaping (BrandID) -> Void) {
        push(makeAdminHomeView(onCreatedBrand: onCreatedBrand))
    }

    func pushAdminBrandRequestGroups() {
        push(makeAdminBrandRequestGroupsView())
    }

    func pushAdminBrandManagement(
        initialBrand: Brand? = nil,
        initialBrandID: BrandID? = nil,
        onUpdatedBrand: ((Brand) -> Void)? = nil
    ) {
        push(makeAdminBrandManagementView(
            initialBrand: initialBrand,
            initialBrandID: initialBrandID,
            onUpdatedBrand: onUpdatedBrand
        ))
    }

    func pushAdminLookbookDeletionManagement(initialBrand: Brand? = nil) {
        push(makeAdminLookbookDeletionManagementView(
            initialBrand: initialBrand,
            allowsDeletionSelection: initialBrand != nil
        ))
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

    func makeBrandRequestView(
        initialBrandName: String,
        onSubmitted: @escaping () -> Void
    ) -> BrandRequestView {
        container.makeBrandRequestView(
            initialBrandName: initialBrandName,
            onSubmitted: onSubmitted,
            coordinator: self
        )
    }

    func makeMyBrandRequestsView(
        initialScope: BrandRequestListScope = .active
    ) -> MyBrandRequestsView {
        container.makeMyBrandRequestsView(
            initialScope: initialScope,
            coordinator: self
        )
    }

    func makeAdminHomeView(
        onCreatedBrand: @escaping (BrandID) -> Void
    ) -> LookbookAdminHomeView {
        container.makeAdminHomeView(
            coordinator: self,
            onCreatedBrand: onCreatedBrand
        )
    }

    func makeAdminBrandRequestGroupsView() -> AdminBrandRequestGroupsView {
        container.makeAdminBrandRequestGroupsView(coordinator: self)
    }

    func makeAdminBrandManagementView(
        initialBrand: Brand? = nil,
        initialBrandID: BrandID? = nil,
        onUpdatedBrand: ((Brand) -> Void)? = nil
    ) -> AdminBrandManagementView {
        container.makeAdminBrandManagementView(
            coordinator: self,
            initialBrand: initialBrand,
            initialBrandID: initialBrandID,
            onUpdatedBrand: onUpdatedBrand
        )
    }

    func makeAdminLookbookDeletionManagementView(
        initialBrand: Brand? = nil,
        allowsDeletionSelection: Bool = true
    ) -> AdminLookbookDeletionManagementView {
        container.makeAdminLookbookDeletionManagementView(
            coordinator: self,
            initialBrand: initialBrand,
            allowsDeletionSelection: allowsDeletionSelection
        )
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
        initialBrandName: String? = nil,
        initialEnglishName: String? = nil,
        onCreatedBrand: @escaping (BrandID) -> Void
    ) -> some View {
        container.makeCreateBrandFlow(
            initialBrandName: initialBrandName,
            initialEnglishName: initialEnglishName,
            onCreatedBrand: onCreatedBrand
        )
    }

    private func replaceTopWithMyBrandRequests(initialScope: BrandRequestListScope) {
        guard let navigationController else {
            assertionFailure("LookbookCoordinator requires an attached UINavigationController.")
            return
        }

        var viewControllers = navigationController.viewControllers
        guard viewControllers.isEmpty == false else {
            pushMyBrandRequests(initialScope: initialScope)
            return
        }

        viewControllers.removeLast()
        let next = UIHostingController(rootView: makeMyBrandRequestsView(initialScope: initialScope))
        viewControllers.append(next)
        navigationController.setViewControllers(viewControllers, animated: true)
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
