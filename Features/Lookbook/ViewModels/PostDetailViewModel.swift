//
//  PostDetailViewModel.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Combine
import Foundation

@MainActor
final class PostDetailScreenViewModel: ObservableObject {
    @Published private(set) var post: LookbookPost?
    @Published private(set) var postUserState: PostUserState?
    @Published private(set) var comments: [Comment] = []
    @Published private(set) var authorDisplays: [UserID: CommentAuthorDisplay] = [:]
    @Published private(set) var visibleCommentCount: Int?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isMutatingLike: Bool = false
    @Published private(set) var isMutatingSave: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var commentErrorMessage: String?
    @Published private(set) var engagementErrorMessage: String?

    private var loadedKey: String?
    private var isRequesting = false
    private var pendingLikeTarget: Bool?
    private var pendingSaveTarget: Bool?
    private var confirmedLikeState: Bool?
    private var confirmedLikeCount: Int?
    private var confirmedSaveState: Bool?
    private var confirmedSaveCount: Int?
    private var prefetchedAvatarPaths: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
    private let avatarThumbnailMaxBytes: Int = 3 * 1024 * 1024
    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    private let useCase: any LoadPostDetailUseCaseProtocol
    private let loadHiddenUserIDsUseCase: any LoadHiddenCommentUserIDsUseCaseProtocol
    private let postUserStateRepository: any PostUserStateRepositoryProtocol
    private let engagementRepository: any PostEngagementRepositoryProtocol
    private let authorProfileStore: CommentAuthorProfileStore
    private let interactionStore: LookbookInteractionStore

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostDetailUseCaseProtocol,
        loadHiddenUserIDsUseCase: any LoadHiddenCommentUserIDsUseCaseProtocol,
        postUserStateRepository: any PostUserStateRepositoryProtocol,
        engagementRepository: any PostEngagementRepositoryProtocol,
        interactionStore: LookbookInteractionStore,
        authorProfileStore: CommentAuthorProfileStore? = nil
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.useCase = useCase
        self.loadHiddenUserIDsUseCase = loadHiddenUserIDsUseCase
        self.postUserStateRepository = postUserStateRepository
        self.engagementRepository = engagementRepository
        self.interactionStore = interactionStore
        self.authorProfileStore = authorProfileStore ?? CommentAuthorProfileStore()
        bindInteractionStore()
    }

    var isMutatingEngagement: Bool {
        isMutatingLike || isMutatingSave
    }

    func loadIfNeeded() async {
        let key = "\(brandID.value)|\(seasonID.value)|\(postID.value)"
        guard loadedKey != key else { return }
        await load()
    }

    func refresh() async {
        loadedKey = nil
        await load()
    }

    func displayItem(for comment: Comment) -> CommentDisplayItem {
        authorProfileStore.displayItem(for: comment)
    }

    func prefetchAuthorAvatars(for comments: [Comment], avatarImageManager: ChatAvatarImageManaging = AvatarImageService.shared) {
        let paths = comments
            .compactMap { authorDisplays[$0.userID]?.avatarPath }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { prefetchedAvatarPaths.contains($0) == false }

        guard paths.isEmpty == false else { return }
        prefetchedAvatarPaths.formUnion(paths)

        Task {
            await avatarImageManager.prefetchAvatars(
                paths: paths,
                maxBytes: avatarThumbnailMaxBytes,
                maxConcurrent: 4
            )
        }
    }

    func toggleLike() async {
        guard let userID = currentUserID else {
            engagementErrorMessage = "로그인이 필요합니다."
            return
        }

        let targetState = !(postUserState?.isLiked ?? false)
        if isMutatingLike == false {
            confirmedLikeState = postUserState?.isLiked ?? false
            confirmedLikeCount = post?.metrics.likeCount ?? 0
        }

        engagementErrorMessage = nil
        applyOptimisticLike(
            targetState,
            postID: postID,
            userID: userID
        )
        pendingLikeTarget = targetState

        guard isMutatingLike == false else { return }

        await drainLikeQueue(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: userID,
            repository: engagementRepository
        )
    }

    func toggleSave() async {
        guard let userID = currentUserID else {
            engagementErrorMessage = "로그인이 필요합니다."
            return
        }

        let targetState = !(postUserState?.isSaved ?? false)
        if isMutatingSave == false {
            confirmedSaveState = postUserState?.isSaved ?? false
            confirmedSaveCount = post?.metrics.saveCount ?? 0
        }

        engagementErrorMessage = nil
        applyOptimisticSave(
            targetState,
            postID: postID,
            userID: userID
        )
        pendingSaveTarget = targetState

        guard isMutatingSave == false else { return }

        await drainSaveQueue(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: userID,
            repository: engagementRepository
        )
    }

    func applyCommentMutation(_ result: CommentMutationResult) {
        guard post?.id == result.postID else { return }
        interactionStore.applyCommentMutation(result)
    }

    func removeCommentFromPreview(_ commentID: CommentID) {
        comments.removeAll { $0.id == commentID }
    }

    private func load() async {
        if isRequesting { return }
        isRequesting = true
        isLoading = true
        errorMessage = nil
        commentErrorMessage = nil
        engagementErrorMessage = nil
        defer {
            isRequesting = false
            isLoading = false
        }

        do {
            let content = try await useCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                hiddenUserIDs: await loadHiddenUserIDs()
            )
            comments = content.comments
            commentErrorMessage = content.commentErrorMessage
            await authorProfileStore.loadMissingAuthors(for: content.comments)
            syncAuthorDisplays()
            let fetchedPostUserState = await fetchPostUserState(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                repository: postUserStateRepository
            )
            post = content.post
            postUserState = fetchedPostUserState
            visibleCommentCount = content.visibleCommentCount
            interactionStore.seed(
                post: content.post,
                visibleCommentCount: content.visibleCommentCount,
                userState: fetchedPostUserState
            )
            loadedKey = "\(brandID.value)|\(seasonID.value)|\(postID.value)"
        } catch {
            post = nil
            postUserState = nil
            comments = []
            visibleCommentCount = nil
            authorProfileStore.reset()
            syncAuthorDisplays()
            errorMessage = "포스트를 불러오지 못했습니다."
            commentErrorMessage = nil
            engagementErrorMessage = nil
        }
    }

    private func fetchPostUserState(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        repository: any PostUserStateRepositoryProtocol
    ) async -> PostUserState? {
        guard let userID = currentUserID else {
            return nil
        }

        do {
            engagementErrorMessage = nil
            return try await repository.fetchPostUserState(
                userID: userID,
                brandID: brandID,
                seasonID: seasonID,
                postID: postID
            )
        } catch {
            engagementErrorMessage = "좋아요와 저장 상태를 불러오지 못했습니다."
            return nil
        }
    }

    private func syncAuthorDisplays() {
        authorDisplays = authorProfileStore.authorDisplays
    }

    private func bindInteractionStore() {
        interactionStore.$postStates
            .compactMap { [postID] states in states[postID] }
            .sink { [weak self] state in
                guard let self else { return }
                self.applyInteractionState(state)
            }
            .store(in: &cancellables)
    }

    private func applyInteractionState(_ state: LookbookPostInteractionState) {
        if var post {
            post.metrics = state.metrics
            self.post = post
        }
        visibleCommentCount = state.visibleCommentCount
        postUserState = state.userState
    }

    private func loadHiddenUserIDs() async -> Set<UserID> {
        guard let currentUserID else { return [] }
        do {
            return try await loadHiddenUserIDsUseCase.execute(currentUserID: currentUserID)
        } catch {
            return []
        }
    }

    private func drainLikeQueue(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        userID: UserID,
        repository: any PostEngagementRepositoryProtocol
    ) async {
        isMutatingLike = true
        defer {
            isMutatingLike = false
            confirmedLikeState = nil
            confirmedLikeCount = nil
        }

        while let target = pendingLikeTarget {
            pendingLikeTarget = nil

            do {
                let result = try await repository.setLike(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID,
                    isLiked: target
                )
                confirmedLikeState = result.isLiked
                confirmedLikeCount = result.metrics.likeCount

                if let pendingLikeTarget,
                   pendingLikeTarget != result.isLiked {
                    applyOptimisticLike(
                        pendingLikeTarget,
                        postID: postID,
                        userID: userID,
                        baseLiked: result.isLiked,
                        baseLikeCount: result.metrics.likeCount
                    )
                    continue
                }

                pendingLikeTarget = nil
                applyLikeResult(result)
            } catch {
                pendingLikeTarget = nil
                restoreConfirmedLike(postID: postID, userID: userID)
                engagementErrorMessage = "좋아요 상태를 변경하지 못했습니다."
                break
            }
        }
    }

    private func drainSaveQueue(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        userID: UserID,
        repository: any PostEngagementRepositoryProtocol
    ) async {
        isMutatingSave = true
        defer {
            isMutatingSave = false
            confirmedSaveState = nil
            confirmedSaveCount = nil
        }

        while let target = pendingSaveTarget {
            pendingSaveTarget = nil

            do {
                let result = try await repository.setSave(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID,
                    isSaved: target
                )
                confirmedSaveState = result.isSaved
                confirmedSaveCount = result.metrics.saveCount

                if let pendingSaveTarget,
                   pendingSaveTarget != result.isSaved {
                    applyOptimisticSave(
                        pendingSaveTarget,
                        postID: postID,
                        userID: userID,
                        baseSaved: result.isSaved,
                        baseSaveCount: result.metrics.saveCount
                    )
                    continue
                }

                pendingSaveTarget = nil
                applySaveResult(result)
            } catch {
                pendingSaveTarget = nil
                restoreConfirmedSave(postID: postID, userID: userID)
                engagementErrorMessage = "저장 상태를 변경하지 못했습니다."
                break
            }
        }
    }

    private func applyOptimisticLike(
        _ isLiked: Bool,
        postID: PostID,
        userID: UserID,
        baseLiked: Bool? = nil,
        baseLikeCount: Int? = nil
    ) {
        let previousLiked = baseLiked ?? postUserState?.isLiked ?? false
        let likeCount = baseLikeCount ?? post?.metrics.likeCount ?? 0

        interactionStore.applyOptimisticLike(
            postID: postID,
            userID: userID,
            isLiked: isLiked,
            baseLiked: previousLiked,
            baseLikeCount: likeCount
        )
    }

    private func applyOptimisticSave(
        _ isSaved: Bool,
        postID: PostID,
        userID: UserID,
        baseSaved: Bool? = nil,
        baseSaveCount: Int? = nil
    ) {
        let previousSaved = baseSaved ?? postUserState?.isSaved ?? false
        let saveCount = baseSaveCount ?? post?.metrics.saveCount ?? 0

        interactionStore.applyOptimisticSave(
            postID: postID,
            userID: userID,
            isSaved: isSaved,
            baseSaved: previousSaved,
            baseSaveCount: saveCount
        )
    }

    private func applyLikeResult(_ result: PostEngagementResult) {
        let shouldApplySave = isMutatingSave == false && pendingSaveTarget == nil
        interactionStore.applyLikeResult(result, shouldApplySave: shouldApplySave)
    }

    private func applySaveResult(_ result: PostEngagementResult) {
        let shouldApplyLike = isMutatingLike == false && pendingLikeTarget == nil
        interactionStore.applySaveResult(result, shouldApplyLike: shouldApplyLike)
    }

    private func restoreConfirmedLike(postID: PostID, userID: UserID) {
        guard let confirmedLikeState else { return }

        interactionStore.restoreLike(
            postID: postID,
            userID: userID,
            isLiked: confirmedLikeState,
            likeCount: confirmedLikeCount
        )
    }

    private func restoreConfirmedSave(postID: PostID, userID: UserID) {
        guard let confirmedSaveState else { return }

        interactionStore.restoreSave(
            postID: postID,
            userID: userID,
            isSaved: confirmedSaveState,
            saveCount: confirmedSaveCount
        )
    }

    private var currentUserID: UserID? {
        let identityKey = LoginManager.shared.getAuthIdentityKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard identityKey.isEmpty == false else { return nil }
        return UserID(value: identityKey)
    }
}
