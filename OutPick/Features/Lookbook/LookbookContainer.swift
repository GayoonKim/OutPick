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
    private enum ShareMoveRoutingError: Error {
        case missingRouter
    }

    let provider: LookbookRepositoryProvider
    let brandAdminSessionStore: BrandAdminSessionStore
    let lookbookHomeViewModel: LookbookHomeViewModel
    let interactionStore: LookbookInteractionStore
    let debugFailureInjectionStore: LookbookDebugFailureInjectionStore
    let currentUserProvider: any CurrentUserProviding
    let currentUserIDProvider: any CurrentUserIDProviding
    private var avatarImageManager: AvatarImageManaging
    private let firebaseRepositories: any FirebaseRepositoryProviding

    private let loadPostCommentsUseCase: any LoadPostCommentsUseCaseProtocol
    private let loadCommentRepliesUseCase: any LoadCommentRepliesUseCaseProtocol
    private let createPostCommentUseCase: any CreatePostCommentUseCaseProtocol
    private let createCommentReplyUseCase: any CreateCommentReplyUseCaseProtocol
    private let commentEngagementInteractionUseCase: CommentEngagementInteractionUseCase
    private let deleteCommentUseCase: any DeleteCommentUseCaseProtocol
    private let reportCommentUseCase: any ReportCommentUseCaseProtocol
    private let blockUserUseCase: any BlockUserUseCaseProtocol
    private let loadHiddenCommentUserIDsUseCase: any LoadHiddenCommentUserIDsUseCaseProtocol
    private let filterHiddenCommentAuthorsUseCase: FilterHiddenCommentAuthorsUseCase
    private let loadSeasonDetailUseCase: any LoadSeasonDetailUseCaseProtocol
    private let loadPostDetailUseCase: any LoadPostDetailUseCaseProtocol
    private let makeLookbookSharedContentUseCase: any MakeLookbookSharedContentUseCaseProtocol
    private var loadShareableJoinedRoomsUseCase: (any LoadShareableJoinedRoomsUseCaseProtocol)?
    private var shareLookbookContentToChatUseCase: (any ShareLookbookContentToChatUseCaseProtocol)?
    private var roomImageManager: (any RoomImageManaging)?
    private weak var appContentRouter: (any AppContentRouting)?

    init(
        provider: LookbookRepositoryProvider = .shared,
        brandAdminSessionStore: BrandAdminSessionStore,
        currentUserProvider: any CurrentUserProviding = LoginManagerCurrentUserProvider(),
        firebaseRepositories: any FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared,
        avatarImageManager: AvatarImageManaging
    ) {
        self.provider = provider
        self.brandAdminSessionStore = brandAdminSessionStore
        self.interactionStore = LookbookInteractionStore()
        self.debugFailureInjectionStore = LookbookDebugFailureInjectionStore()
        #if DEBUG
        LookbookDebugFailureLaunchArguments.apply(to: debugFailureInjectionStore)
        #endif
        self.currentUserProvider = currentUserProvider
        self.currentUserIDProvider = LookbookCurrentUserIDProvider(currentUserProvider: currentUserProvider)
        self.firebaseRepositories = firebaseRepositories
        self.avatarImageManager = avatarImageManager
        self.loadPostCommentsUseCase = LoadPostCommentsUseCase(
            commentRepository: provider.commentRepository
        )
        self.loadCommentRepliesUseCase = LoadCommentRepliesUseCase(
            commentRepository: provider.commentRepository
        )
        self.createPostCommentUseCase = CreatePostCommentUseCase(
            repository: provider.commentWritingRepository,
            debugFailureInjectionStore: debugFailureInjectionStore
        )
        self.createCommentReplyUseCase = CreateCommentReplyUseCase(
            repository: provider.commentWritingRepository,
            debugFailureInjectionStore: debugFailureInjectionStore
        )
        self.commentEngagementInteractionUseCase = CommentEngagementInteractionUseCase(
            repository: provider.commentEngagementRepository,
            commentInteractionStore: interactionStore,
            debugFailureInjectionStore: debugFailureInjectionStore
        )
        self.deleteCommentUseCase = DeleteCommentUseCase(
            repository: provider.commentWritingRepository,
            debugFailureInjectionStore: debugFailureInjectionStore
        )
        self.reportCommentUseCase = ReportCommentUseCase(
            repository: provider.commentSafetyRepository,
            debugFailureInjectionStore: debugFailureInjectionStore
        )
        self.blockUserUseCase = BlockUserUseCase(
            repository: provider.userBlockRepository,
            debugFailureInjectionStore: debugFailureInjectionStore
        )
        self.loadHiddenCommentUserIDsUseCase = LoadHiddenCommentUserIDsUseCase(
            repository: provider.userBlockRepository
        )
        self.filterHiddenCommentAuthorsUseCase = FilterHiddenCommentAuthorsUseCase()
        self.loadSeasonDetailUseCase = LoadSeasonDetailUseCase(
            seasonRepository: provider.seasonRepository,
            postRepository: provider.postRepository
        )
        self.loadPostDetailUseCase = LoadPostDetailUseCase(
            postRepository: provider.postRepository,
            commentRepository: provider.commentRepository
        )
        self.makeLookbookSharedContentUseCase = MakeLookbookSharedContentUseCase(
            brandRepository: provider.brandRepository,
            seasonRepository: provider.seasonRepository
        )
        self.lookbookHomeViewModel = LookbookHomeViewModel(
            repo: provider.brandRepository,
            brandAdminSessionStore: brandAdminSessionStore,
            brandImageCache: provider.brandImageCache,
            initialBrandLimit: 12,
            prefetchLogoCount: 4
        )
    }

    func configureLookbookChatShare(
        loadShareableJoinedRoomsUseCase: any LoadShareableJoinedRoomsUseCaseProtocol,
        shareLookbookContentToChatUseCase: any ShareLookbookContentToChatUseCaseProtocol,
        roomImageManager: any RoomImageManaging,
        avatarImageManager: any AvatarImageManaging
    ) {
        self.loadShareableJoinedRoomsUseCase = loadShareableJoinedRoomsUseCase
        self.shareLookbookContentToChatUseCase = shareLookbookContentToChatUseCase
        self.roomImageManager = roomImageManager
        self.avatarImageManager = avatarImageManager
    }

    func configureAppContentRouter(_ appContentRouter: any AppContentRouting) {
        self.appContentRouter = appContentRouter
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
            },
            importManagementSheetFactory: { [self] in
                AnyView(
                    self.makeSeasonImportManagementView(
                        brandID: brand.id
                    )
                )
            },
            shareSheetFactory: { [self] target, onCompleted in
                self.makeLookbookShareSheet(
                    target: target,
                    onCompleted: onCompleted
                )
            },
            onShareMove: { [weak self] completion in
                guard let appContentRouter = self?.appContentRouter else {
                    throw ShareMoveRoutingError.missingRouter
                }
                try await appContentRouter.openJoinedChatRoom(roomID: completion.roomID)
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
            coordinator: coordinator,
            shareSheetFactory: { [self] target, onCompleted in
                self.makeLookbookShareSheet(
                    target: target,
                    onCompleted: onCompleted
                )
            },
            onShareMove: { [weak self] completion in
                guard let appContentRouter = self?.appContentRouter else {
                    throw ShareMoveRoutingError.missingRouter
                }
                try await appContentRouter.openJoinedChatRoom(roomID: completion.roomID)
            }
        )
    }

    func makeLikedView(coordinator: LookbookCoordinator) -> LikedView {
        LikedView(
            viewModel: makeLikedViewModel(),
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
            brandImageCache: provider.brandImageCache,
            avatarImageManager: avatarImageManager,
            shareSheetFactory: { [self] target, onCompleted in
                self.makeLookbookShareSheet(
                    target: target,
                    onCompleted: onCompleted
                )
            },
            onShareMove: { [weak self] completion in
                guard let appContentRouter = self?.appContentRouter else {
                    throw ShareMoveRoutingError.missingRouter
                }
                try await appContentRouter.openJoinedChatRoom(roomID: completion.roomID)
            }
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
            brandUserStateRepository: provider.brandUserStateRepository,
            brandEngagementInteractionUseCase: BrandEngagementInteractionUseCase(
                repository: provider.brandEngagementRepository,
                brandInteractionStore: interactionStore,
                debugFailureInjectionStore: debugFailureInjectionStore
            ),
            brandInteractionStore: interactionStore,
            currentUserIDProvider: currentUserIDProvider,
            brandImageCache: provider.brandImageCache,
            maxBytes: 1_000_000
        )
    }

    func makeLikedViewModel() -> LikedViewModel {
        LikedViewModel(
            likedBrandsUseCase: LoadLikedBrandsUseCase(
                brandUserStateRepository: provider.brandUserStateRepository,
                brandRepository: provider.brandRepository
            ),
            likedSeasonsUseCase: LoadLikedSeasonsUseCase(
                seasonUserStateRepository: provider.seasonUserStateRepository,
                seasonRepository: provider.seasonRepository
            ),
            likedPostsUseCase: LoadLikedPostsUseCase(
                postUserStateRepository: provider.postUserStateRepository,
                postRepository: provider.postRepository
            ),
            brandEngagementRepository: provider.brandEngagementRepository,
            seasonEngagementRepository: provider.seasonEngagementRepository,
            postEngagementRepository: provider.postEngagementRepository,
            brandInteractionStore: interactionStore,
            seasonInteractionStore: interactionStore,
            postInteractionStore: interactionStore,
            currentUserIDProvider: currentUserIDProvider,
            brandImageCache: provider.brandImageCache
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
            seasonUserStateRepository: provider.seasonUserStateRepository,
            seasonEngagementRepository: provider.seasonEngagementRepository,
            seasonInteractionStore: interactionStore,
            brandImageCache: provider.brandImageCache,
            postInteractionStore: interactionStore,
            currentUserIDProvider: currentUserIDProvider,
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
            loadHiddenUserIDsUseCase: loadHiddenCommentUserIDsUseCase,
            postUserStateRepository: provider.postUserStateRepository,
            engagementInteractionUseCase: PostEngagementInteractionUseCase(
                repository: provider.postEngagementRepository,
                postInteractionStore: interactionStore,
                debugFailureInjectionStore: debugFailureInjectionStore
            ),
            postInteractionStore: interactionStore,
            commentInteractionStore: interactionStore,
            currentUserIDProvider: currentUserIDProvider
        )
    }

    func makeSeasonCandidateSelectionView(
        createdBrand: CreateBrandViewModel.CreatedBrand,
        onToolbarCloseVisibilityChange: @escaping (Bool) -> Void = { _ in },
        onDismiss: @escaping () -> Void
    ) -> CreateBrandCandidateSelectionView {
        CreateBrandCandidateSelectionView(
            createdBrand: createdBrand,
            loadSelectableSeasonCandidatesUseCase: LoadSelectableSeasonCandidatesUseCase(
                candidateRepository: provider.seasonCandidateRepository,
                seasonImportJobRepository: provider.seasonImportJobRepository
            ),
            refreshSeasonCandidatesUseCase: provider.seasonCandidateDiscoveryRepository,
            startSeasonImportExtractionUseCase: StartSeasonImportExtractionUseCase(
                importJobRequestingRepository: provider.seasonImportJobRequestingRepository,
                seasonImportJobRepository: provider.seasonImportJobRepository
            ),
            discoveryErrorMessage: nil,
            emptySelectionButtonTitle: "닫기",
            onToolbarCloseVisibilityChange: onToolbarCloseVisibilityChange,
            onComplete: onDismiss
        )
    }

    func makeSeasonAdditionSheet(
        brand: Brand,
        onDismiss: @escaping () -> Void
    ) -> some View {
        SeasonAdditionSheetView(
            createdBrand: CreateBrandViewModel.CreatedBrand(
                id: brand.id,
                name: brand.name,
                websiteURL: brand.websiteURL,
                lookbookArchiveURL: brand.lookbookArchiveURL,
                hasLogoAsset: brand.logoThumbPath != nil
            ),
            container: self,
            onDismiss: onDismiss
        )
    }

    func makeSeasonImportManagementView(
        brandID: BrandID
    ) -> SeasonImportManagementView {
        SeasonImportManagementView(
            viewModel: SeasonImportManagementViewModel(
                brandID: brandID,
                useCase: ManageSeasonImportJobsUseCase(
                    jobRepository: provider.seasonImportJobRepository,
                    retryRepository: provider.seasonAssetRetryRepository
                )
            )
        )
    }

    func makeLookbookShareSheet(
        target: LookbookShareTarget,
        onCompleted: @escaping (LookbookChatShareViewModel.Completion) -> Void
    ) -> AnyView {
        guard
            let loadShareableJoinedRoomsUseCase,
            let shareLookbookContentToChatUseCase,
            let roomImageManager
        else {
            return AnyView(
                LookbookShareUnavailableView()
            )
        }

        let viewModel = LookbookChatShareViewModel(
            target: target,
            makeSharedContentUseCase: makeLookbookSharedContentUseCase,
            loadRoomsUseCase: loadShareableJoinedRoomsUseCase,
            shareUseCase: shareLookbookContentToChatUseCase
        )
        return AnyView(
            LookbookShareSheetView(
                viewModel: viewModel,
                brandImageCache: provider.brandImageCache,
                roomImageManager: roomImageManager,
                onCompleted: onCompleted
            )
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
            createUseCase: createPostCommentUseCase,
            commentEngagementInteractionUseCase: commentEngagementInteractionUseCase,
            deleteUseCase: deleteCommentUseCase,
            reportUseCase: reportCommentUseCase,
            blockUseCase: blockUserUseCase,
            commentUserStateRepository: provider.commentUserStateRepository,
            loadHiddenUserIDsUseCase: loadHiddenCommentUserIDsUseCase,
            filterHiddenAuthorsUseCase: filterHiddenCommentAuthorsUseCase,
            commentInteractionStore: interactionStore,
            currentUserIDProvider: currentUserIDProvider,
            avatarImageManager: avatarImageManager
        )
    }

    func makeCommentsSheet(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        navigationCoordinator: LookbookCoordinator,
        commentCoordinator: PostCommentCoordinator
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
            avatarImageManager: avatarImageManager,
            currentUserProvider: currentUserProvider,
            firebaseRepositories: firebaseRepositories
        )
    }

    func makeRepliesSheet(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentComment: Comment
    ) -> PostCommentRepliesSheetView {
        PostCommentRepliesSheetView(
            viewModel: makePostCommentRepliesViewModel(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentComment: parentComment
            ),
            avatarImageManager: avatarImageManager,
            currentUserProvider: currentUserProvider,
            firebaseRepositories: firebaseRepositories
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
            commentEngagementInteractionUseCase: commentEngagementInteractionUseCase,
            deleteUseCase: deleteCommentUseCase,
            reportUseCase: reportCommentUseCase,
            blockUseCase: blockUserUseCase,
            commentUserStateRepository: provider.commentUserStateRepository,
            loadHiddenUserIDsUseCase: loadHiddenCommentUserIDsUseCase,
            filterHiddenAuthorsUseCase: filterHiddenCommentAuthorsUseCase,
            commentInteractionStore: interactionStore,
            currentUserIDProvider: currentUserIDProvider,
            avatarImageManager: avatarImageManager
        )
    }
}

private struct SeasonAdditionSheetView: View {
    let createdBrand: CreateBrandViewModel.CreatedBrand
    let container: LookbookContainer
    let onDismiss: () -> Void

    @State private var isToolbarCloseVisible: Bool = true

    var body: some View {
        NavigationView {
            container.makeSeasonCandidateSelectionView(
                createdBrand: createdBrand,
                onToolbarCloseVisibilityChange: { isVisible in
                    isToolbarCloseVisible = isVisible
                },
                onDismiss: onDismiss
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        onDismiss()
                    }
                    .opacity(isToolbarCloseVisible ? 1 : 0)
                    .disabled(isToolbarCloseVisible == false)
                    .accessibilityHidden(isToolbarCloseVisible == false)
                }
            }
            .navigationBarHidden(isToolbarCloseVisible == false)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
