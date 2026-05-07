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
    private let deleteCommentUseCase: any DeleteCommentUseCaseProtocol
    private let reportCommentUseCase: any ReportCommentUseCaseProtocol
    private let blockUserUseCase: any BlockUserUseCaseProtocol
    private let loadBlockedUsersUseCase: any LoadBlockedUsersUseCaseProtocol
    private let filterBlockedCommentAuthorsUseCase: FilterBlockedCommentAuthorsUseCase
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
        self.deleteCommentUseCase = DeleteCommentUseCase(
            repository: provider.commentWritingRepository
        )
        self.reportCommentUseCase = ReportCommentUseCase(
            repository: provider.commentSafetyRepository
        )
        self.blockUserUseCase = BlockUserUseCase(
            repository: provider.userBlockRepository
        )
        self.loadBlockedUsersUseCase = LoadBlockedUsersUseCase(
            repository: provider.userBlockRepository
        )
        self.filterBlockedCommentAuthorsUseCase = FilterBlockedCommentAuthorsUseCase()
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

    func makeBrandDetailView(
        brand: Brand,
        coordinator: LookbookCoordinator
    ) -> BrandDetailView {
        BrandDetailView(
            brand: brand,
            viewModel: makeBrandDetailViewModel(),
            brandImageCache: provider.brandImageCache,
            coordinator: coordinator,
            seasonAdditionSheetFactory: { [self] onDismiss in
                return AnyView(
                    self.makeSeasonAdditionSheet(
                        brand: brand,
                        onDismiss: onDismiss
                    )
                )
            }
        )
    }

    func makeSeasonDetailView(
        brandID: BrandID,
        seasonID: SeasonID,
        coordinator: LookbookCoordinator
    ) -> SeasonDetailView {
        SeasonDetailView(
            brandID: brandID,
            seasonID: seasonID,
            viewModel: makeSeasonDetailViewModel(
                brandID: brandID,
                seasonID: seasonID
            ),
            brandImageCache: provider.brandImageCache,
            coordinator: coordinator
        )
    }

    func makePostDetailView(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        coordinator: LookbookCoordinator
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
            coordinator: coordinator,
            commentCoordinator: coordinator.makePostCommentCoordinator(),
            brandImageCache: provider.brandImageCache
        )
    }

    func makeCreateBrandFlow(
        onCreatedBrand: @escaping (BrandID) -> Void
    ) -> some View {
        CreateBrandFlowView(
            provider: provider,
            onFinished: { createdBrandID in
                guard let createdBrandID else { return }
                onCreatedBrand(createdBrandID)
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

    func makeSeasonAdditionSheet(
        brand: Brand,
        onDismiss: @escaping () -> Void
    ) -> some View {
        NavigationView {
            makeSeasonCandidateSelectionView(
                createdBrand: CreateBrandViewModel.CreatedBrand(
                    id: brand.id,
                    name: brand.name,
                    websiteURL: brand.websiteURL,
                    lookbookArchiveURL: brand.lookbookArchiveURL,
                    hasLogoAsset: brand.logoThumbPath != nil
                ),
                onDismiss: onDismiss
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        onDismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
            createUseCase: createPostCommentUseCase,
            deleteUseCase: deleteCommentUseCase,
            reportUseCase: reportCommentUseCase,
            blockUseCase: blockUserUseCase
        )
    }

    func makeCommentsSheet(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        navigationCoordinator: LookbookCoordinator,
        commentCoordinator: PostCommentCoordinator,
        onCommentSubmitted: @escaping (CommentMutationResult) -> Void,
        onCommentDeleted: @escaping (CommentDeletionResult) -> Void
    ) -> PostCommentsSheetView {
        PostCommentsSheetView(
            viewModel: makePostCommentsViewModel(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID
            ),
            navigationCoordinator: navigationCoordinator,
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            coordinator: commentCoordinator,
            onCommentSubmitted: onCommentSubmitted,
            onCommentDeleted: onCommentDeleted
        )
    }

    func makeRepliesSheet(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentComment: Comment,
        onReplySubmitted: @escaping (CommentMutationResult) -> Void,
        onCommentDeleted: @escaping (CommentDeletionResult) -> Void
    ) -> PostCommentRepliesSheetView {
        PostCommentRepliesSheetView(
            viewModel: makePostCommentRepliesViewModel(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentComment: parentComment
            ),
            onReplySubmitted: onReplySubmitted,
            onCommentDeleted: onCommentDeleted
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
            createUseCase: createCommentReplyUseCase,
            deleteUseCase: deleteCommentUseCase,
            reportUseCase: reportCommentUseCase,
            blockUseCase: blockUserUseCase
        )
    }
}
