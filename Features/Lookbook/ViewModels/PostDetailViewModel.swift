//
//  PostDetailViewModel.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

@MainActor
final class PostDetailScreenViewModel: ObservableObject {
    @Published private(set) var post: LookbookPost?
    @Published private(set) var postUserState: PostUserState?
    @Published private(set) var comments: [Comment] = []
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

    var isMutatingEngagement: Bool {
        isMutatingLike || isMutatingSave
    }

    func loadIfNeeded(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostDetailUseCaseProtocol,
        postUserStateRepository: any PostUserStateRepositoryProtocol
    ) async {
        let key = "\(brandID.value)|\(seasonID.value)|\(postID.value)"
        guard loadedKey != key else { return }
        await load(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            useCase: useCase,
            postUserStateRepository: postUserStateRepository
        )
    }

    func refresh(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostDetailUseCaseProtocol,
        postUserStateRepository: any PostUserStateRepositoryProtocol
    ) async {
        loadedKey = nil
        await load(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            useCase: useCase,
            postUserStateRepository: postUserStateRepository
        )
    }

    func toggleLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        repository: any PostEngagementRepositoryProtocol
    ) async {
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
            repository: repository
        )
    }

    func toggleSave(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        repository: any PostEngagementRepositoryProtocol
    ) async {
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
            repository: repository
        )
    }

    private func load(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostDetailUseCaseProtocol,
        postUserStateRepository: any PostUserStateRepositoryProtocol
    ) async {
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
                postID: postID
            )
            post = content.post
            comments = content.comments
            commentErrorMessage = content.commentErrorMessage
            postUserState = await fetchPostUserState(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                repository: postUserStateRepository
            )
            loadedKey = "\(brandID.value)|\(seasonID.value)|\(postID.value)"
        } catch {
            post = nil
            postUserState = nil
            comments = []
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
        let likeDelta = isLiked == previousLiked ? 0 : (isLiked ? 1 : -1)

        if var post {
            post.metrics = PostMetrics(
                likeCount: max(0, likeCount + likeDelta),
                commentCount: post.metrics.commentCount,
                replacementCount: post.metrics.replacementCount,
                saveCount: post.metrics.saveCount,
                viewCount: post.metrics.viewCount
            )
            self.post = post
        }

        postUserState = PostUserState(
            postID: postID,
            userID: userID,
            isLiked: isLiked,
            isSaved: postUserState?.isSaved ?? false,
            updatedAt: Date()
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
        let saveDelta = isSaved == previousSaved ? 0 : (isSaved ? 1 : -1)

        if var post {
            post.metrics = PostMetrics(
                likeCount: post.metrics.likeCount,
                commentCount: post.metrics.commentCount,
                replacementCount: post.metrics.replacementCount,
                saveCount: max(0, saveCount + saveDelta),
                viewCount: post.metrics.viewCount
            )
            self.post = post
        }

        postUserState = PostUserState(
            postID: postID,
            userID: userID,
            isLiked: postUserState?.isLiked ?? false,
            isSaved: isSaved,
            updatedAt: Date()
        )
    }

    private func applyLikeResult(_ result: PostEngagementResult) {
        let shouldApplySave = isMutatingSave == false && pendingSaveTarget == nil
        updatePostMetrics(
            result.metrics,
            likeCount: result.metrics.likeCount,
            saveCount: shouldApplySave ? result.metrics.saveCount : nil
        )

        postUserState = PostUserState(
            postID: result.postID,
            userID: result.userID,
            isLiked: result.isLiked,
            isSaved: shouldApplySave ? result.isSaved : (postUserState?.isSaved ?? false),
            updatedAt: Date()
        )
    }

    private func applySaveResult(_ result: PostEngagementResult) {
        let shouldApplyLike = isMutatingLike == false && pendingLikeTarget == nil
        updatePostMetrics(
            result.metrics,
            likeCount: shouldApplyLike ? result.metrics.likeCount : nil,
            saveCount: result.metrics.saveCount
        )

        postUserState = PostUserState(
            postID: result.postID,
            userID: result.userID,
            isLiked: shouldApplyLike ? result.isLiked : (postUserState?.isLiked ?? false),
            isSaved: result.isSaved,
            updatedAt: Date()
        )
    }

    private func restoreConfirmedLike(postID: PostID, userID: UserID) {
        guard let confirmedLikeState else { return }

        if let confirmedLikeCount {
            updatePostMetrics(nil, likeCount: confirmedLikeCount, saveCount: nil)
        }

        postUserState = PostUserState(
            postID: postID,
            userID: userID,
            isLiked: confirmedLikeState,
            isSaved: postUserState?.isSaved ?? false,
            updatedAt: Date()
        )
    }

    private func restoreConfirmedSave(postID: PostID, userID: UserID) {
        guard let confirmedSaveState else { return }

        if let confirmedSaveCount {
            updatePostMetrics(nil, likeCount: nil, saveCount: confirmedSaveCount)
        }

        postUserState = PostUserState(
            postID: postID,
            userID: userID,
            isLiked: postUserState?.isLiked ?? false,
            isSaved: confirmedSaveState,
            updatedAt: Date()
        )
    }

    private func updatePostMetrics(
        _ authoritativeMetrics: PostMetrics?,
        likeCount: Int?,
        saveCount: Int?
    ) {
        guard var post else { return }

        let baseMetrics = authoritativeMetrics ?? post.metrics
        post.metrics = PostMetrics(
            likeCount: max(0, likeCount ?? post.metrics.likeCount),
            commentCount: baseMetrics.commentCount,
            replacementCount: baseMetrics.replacementCount,
            saveCount: max(0, saveCount ?? post.metrics.saveCount),
            viewCount: baseMetrics.viewCount
        )
        self.post = post
    }

    private var currentUserID: UserID? {
        let identityKey = LoginManager.shared.getAuthIdentityKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard identityKey.isEmpty == false else { return nil }
        return UserID(value: identityKey)
    }
}
