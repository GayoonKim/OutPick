//
//  AppContainer.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import Foundation
import SwiftUI

@MainActor
final class LookbookContainer {
    let provider: LookbookRepositoryProvider
    let brandAdminSessionStore: BrandAdminSessionStore
    let lookbookHomeViewModel: LookbookHomeViewModel

    private let loadPostCommentsUseCase: any LoadPostCommentsUseCaseProtocol
    private let loadCommentRepliesUseCase: any LoadCommentRepliesUseCaseProtocol
    private let createPostCommentUseCase: any CreatePostCommentUseCaseProtocol
    private let createCommentReplyUseCase: any CreateCommentReplyUseCaseProtocol
    private let loadSeasonDetailUseCase: any LoadSeasonDetailUseCaseProtocol
    private let loadPostDetailUseCase: any LoadPostDetailUseCaseProtocol

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
        self.loadSeasonDetailUseCase = LoadSeasonDetailUseCase(
            seasonRepository: provider.seasonRepository,
            postRepository: provider.postRepository
        )
        self.loadPostDetailUseCase = LoadPostDetailUseCase(
            postRepository: provider.postRepository,
            commentRepository: provider.commentRepository
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

    func makeBrandDetailView(brand: Brand) -> BrandDetailView {
        BrandDetailView(
            brand: brand,
            viewModel: makeBrandDetailViewModel(),
            brandImageCache: provider.brandImageCache,
            seasonDestination: { [self] season in
                return AnyView(
                    self.makeSeasonDetailView(
                        brandID: season.brandID,
                        seasonID: season.id
                    )
                )
            },
            seasonCandidateSelectionFactory: { [self] createdBrand, onDismiss in
                return AnyView(
                    self.makeSeasonCandidateSelectionView(
                        createdBrand: createdBrand,
                        onDismiss: onDismiss
                    )
                )
            }
        )
    }

    func makeSeasonDetailView(
        brandID: BrandID,
        seasonID: SeasonID
    ) -> SeasonDetailView {
        SeasonDetailView(
            brandID: brandID,
            seasonID: seasonID,
            viewModel: makeSeasonDetailViewModel(
                brandID: brandID,
                seasonID: seasonID
            ),
            brandImageCache: provider.brandImageCache,
            postDestination: { [self] post in
                return AnyView(
                    self.makePostDetailView(
                        brandID: post.brandID,
                        seasonID: post.seasonID,
                        postID: post.id
                    )
                )
            }
        )
    }

    func makePostDetailView(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) -> PostDetailView {
        PostDetailView(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            viewModel: makePostDetailViewModel(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID
            ),
            commentCoordinator: makePostCommentCoordinator(),
            brandImageCache: provider.brandImageCache,
            commentsViewModelFactory: { [self] in
                return self.makePostCommentsViewModel(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID
                )
            },
            repliesViewModelFactory: { [self] parentComment in
                return self.makePostCommentRepliesViewModel(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID,
                    parentComment: parentComment
                )
            }
        )
    }

    func makeBrandDetailViewModel() -> BrandDetailViewModel {
        BrandDetailViewModel(
            seasonRepository: provider.seasonRepository,
            brandImageCache: provider.brandImageCache,
            maxBytes: 1_000_000
        )
    }

    func makeSeasonDetailViewModel(
        brandID: BrandID,
        seasonID: SeasonID
    ) -> SeasonDetailViewModel {
        SeasonDetailViewModel(
            brandID: brandID,
            seasonID: seasonID,
            useCase: loadSeasonDetailUseCase,
            brandImageCache: provider.brandImageCache,
            maxBytes: 1_500_000
        )
    }

    func makePostDetailViewModel(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) -> PostDetailScreenViewModel {
        PostDetailScreenViewModel(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            useCase: loadPostDetailUseCase,
            postUserStateRepository: provider.postUserStateRepository,
            engagementRepository: provider.postEngagementRepository
        )
    }

    func makeSeasonCandidateSelectionView(
        createdBrand: CreateBrandViewModel.CreatedBrand,
        onDismiss: @escaping () -> Void
    ) -> CreateBrandCandidateSelectionView {
        CreateBrandCandidateSelectionView(
            createdBrand: createdBrand,
            loadSelectableSeasonCandidatesUseCase: LoadSelectableSeasonCandidatesUseCase(
                candidateRepository: provider.seasonCandidateRepository,
                seasonImportJobRepository: provider.seasonImportJobRepository
            ),
            startSeasonImportExtractionUseCase: StartSeasonImportExtractionUseCase(
                processingRepository: provider.seasonImportJobProcessingRepository,
                seasonImportJobRepository: provider.seasonImportJobRepository
            ),
            discoveryErrorMessage: nil,
            emptySelectionButtonTitle: "닫기",
            onComplete: onDismiss
        )
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
