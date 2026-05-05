//
//  LookbookCoordinator.swift
//  OutPick
//
//  Created by Codex on 5/5/26.
//

import SwiftUI

@MainActor
final class LookbookCoordinator {
    private let container: LookbookContainer

    init(container: LookbookContainer) {
        self.container = container
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

    func presentComments(using coordinator: PostCommentCoordinator) {
        coordinator.presentComments()
    }

    func dismissComments(using coordinator: PostCommentCoordinator) {
        coordinator.dismissComments()
    }

    func makeCommentsSheet(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentCoordinator: PostCommentCoordinator,
        onCommentSubmitted: @escaping (CommentMutationResult) -> Void
    ) -> some View {
        container.makeCommentsSheet(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            navigationCoordinator: self,
            commentCoordinator: commentCoordinator,
            onCommentSubmitted: onCommentSubmitted
        )
    }

    func makeRepliesSheet(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentComment: Comment,
        onReplySubmitted: @escaping (CommentMutationResult) -> Void
    ) -> some View {
        container.makeRepliesSheet(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            parentComment: parentComment,
            onReplySubmitted: onReplySubmitted
        )
    }
}
