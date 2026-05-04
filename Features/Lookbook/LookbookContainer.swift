//
//  AppContainer.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import Foundation

@MainActor
final class LookbookContainer {
    let provider: LookbookRepositoryProvider
    let brandAdminSessionStore: BrandAdminSessionStore
    let lookbookHomeViewModel: LookbookHomeViewModel

    private let loadPostCommentsUseCase: any LoadPostCommentsUseCaseProtocol
    private let loadCommentRepliesUseCase: any LoadCommentRepliesUseCaseProtocol
    private let createPostCommentUseCase: any CreatePostCommentUseCaseProtocol
    private let createCommentReplyUseCase: any CreateCommentReplyUseCaseProtocol

    init(
        provider: LookbookRepositoryProvider = .shared,
        brandAdminSessionStore: BrandAdminSessionStore
    ) {
        self.provider = provider
        self.brandAdminSessionStore = brandAdminSessionStore
        self.loadPostCommentsUseCase = LoadPostCommentsUseCase(
            commentRepository: provider.commentRepository
        )
        self.loadCommentRepliesUseCase = LoadCommentRepliesUseCase(
            commentRepository: provider.commentRepository
        )
        self.createPostCommentUseCase = CreatePostCommentUseCase(
            repository: provider.commentWritingRepository
        )
        self.createCommentReplyUseCase = CreateCommentReplyUseCase(
            repository: provider.commentWritingRepository
        )

        self.lookbookHomeViewModel = LookbookHomeViewModel(
            repo: provider.brandRepository,
            brandAdminSessionStore: brandAdminSessionStore,
            brandImageCache: provider.brandImageCache,
            initialBrandLimit: 12,
            prefetchLogoCount: 4
        )
    }

    func preloadLookbook() {
        Task { await lookbookHomeViewModel.loadInitialPageIfNeeded() }
    }

    func makePostCommentCoordinator() -> PostCommentCoordinator {
        PostCommentCoordinator()
    }

    func makePostCommentsViewModel(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) -> PostCommentsViewModel {
        PostCommentsViewModel(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            useCase: loadPostCommentsUseCase,
            createUseCase: createPostCommentUseCase
        )
    }

    func makePostCommentRepliesViewModel(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentComment: Comment
    ) -> PostCommentRepliesViewModel {
        PostCommentRepliesViewModel(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            parentComment: parentComment,
            useCase: loadCommentRepliesUseCase,
            createUseCase: createCommentReplyUseCase
        )
    }
}
