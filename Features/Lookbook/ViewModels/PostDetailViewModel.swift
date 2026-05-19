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
    private var prefetchedAvatarPaths: Set<String> = []
    private var interactionPinScope: InteractionPinScope?
    private var pinnedCommentIDs: Set<CommentID> = []
    private var commentPinScopes: [CommentID: InteractionPinScope] = [:]
    private var commentStateInvalidationTask: Task<Void, Never>?
    private var postStateInvalidationTask: Task<Void, Never>?
    private var representativeCommentInvalidationTask: Task<Void, Never>?
    private var isRefreshingRepresentativeComment: Bool = false
    private let avatarThumbnailMaxBytes: Int = 3 * 1024 * 1024
    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    private let useCase: any LoadPostDetailUseCaseProtocol
    private let loadHiddenUserIDsUseCase: any LoadHiddenCommentUserIDsUseCaseProtocol
    private let postUserStateRepository: any PostUserStateRepositoryProtocol
    private let engagementInteractionUseCase: PostEngagementInteractionUseCase
    private let authorProfileStore: CommentAuthorProfileStore
    private let postInteractionStore: any PostInteractionManaging
    private let commentInteractionStore: any CommentInteractionManaging
    private let currentUserIDProvider: any CurrentUserIDProviding

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostDetailUseCaseProtocol,
        loadHiddenUserIDsUseCase: any LoadHiddenCommentUserIDsUseCaseProtocol,
        postUserStateRepository: any PostUserStateRepositoryProtocol,
        engagementInteractionUseCase: PostEngagementInteractionUseCase,
        postInteractionStore: any PostInteractionManaging,
        commentInteractionStore: any CommentInteractionManaging,
        currentUserIDProvider: any CurrentUserIDProviding,
        authorProfileStore: CommentAuthorProfileStore? = nil
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.useCase = useCase
        self.loadHiddenUserIDsUseCase = loadHiddenUserIDsUseCase
        self.postUserStateRepository = postUserStateRepository
        self.engagementInteractionUseCase = engagementInteractionUseCase
        self.postInteractionStore = postInteractionStore
        self.commentInteractionStore = commentInteractionStore
        self.currentUserIDProvider = currentUserIDProvider
        self.authorProfileStore = authorProfileStore ?? CommentAuthorProfileStore(
            currentUserIDProvider: currentUserIDProvider
        )
        bindInteractionStore()
    }

    deinit {
        commentStateInvalidationTask?.cancel()
        postStateInvalidationTask?.cancel()
        representativeCommentInvalidationTask?.cancel()
    }

    var isMutatingEngagement: Bool {
        isMutatingLike || isMutatingSave
    }

    func loadIfNeeded() async {
        ensureInteractionPinScope()
        let key = "\(brandID.value)|\(seasonID.value)|\(postID.value)"
        guard loadedKey != key else { return }
        await load()
    }

    func refresh() async {
        ensureInteractionPinScope()
        loadedKey = nil
        await load()
    }

    func displayItem(for comment: Comment) -> CommentDisplayItem {
        authorProfileStore.displayItem(for: comment)
    }

    func displayReplyCount(for comment: Comment) -> Int {
        commentInteractionStore.replyCount(for: comment)
    }

    func displayLikeCount(for comment: Comment) -> Int {
        commentInteractionStore.likeCount(for: comment)
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

        engagementErrorMessage = nil
        let outcome = await engagementInteractionUseCase.toggleLike(
            input: engagementInput(userID: userID),
            onMutationStateChanged: { [weak self] isMutating in
                self?.isMutatingLike = isMutating
            }
        )
        engagementErrorMessage = outcome.errorMessage
    }

    func toggleSave() async {
        guard let userID = currentUserID else {
            engagementErrorMessage = "로그인이 필요합니다."
            return
        }

        engagementErrorMessage = nil
        let outcome = await engagementInteractionUseCase.toggleSave(
            input: engagementInput(userID: userID),
            onMutationStateChanged: { [weak self] isMutating in
                self?.isMutatingSave = isMutating
            }
        )
        engagementErrorMessage = outcome.errorMessage
    }

    func refreshRepresentativeComment() async {
        guard let post, isRefreshingRepresentativeComment == false else { return }

        isRefreshingRepresentativeComment = true
        defer {
            isRefreshingRepresentativeComment = false
        }

        do {
            let content = try await useCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                hiddenUserIDs: await loadHiddenUserIDs()
            )
            comments = filterVisibleInteractionComments(content.comments)
            updatePinnedCommentIDs()
            commentErrorMessage = content.commentErrorMessage
            await authorProfileStore.loadMissingAuthors(for: comments)
            syncAuthorDisplays()
            visibleCommentCount = content.visibleCommentCount

            var updatedPost = post
            updatedPost.metrics = content.post.metrics
            self.post = updatedPost
            postInteractionStore.seed(
                post: updatedPost,
                visibleCommentCount: content.visibleCommentCount,
                userState: postUserState
            )
        } catch {
            commentErrorMessage = "댓글을 불러오지 못했습니다."
        }
    }

    func clearEngagementError() {
        engagementErrorMessage = nil
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
            async let fetchedPostUserState = fetchPostUserState(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                repository: postUserStateRepository
            )
            let content = try await useCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                hiddenUserIDs: await loadHiddenUserIDs()
            )
            
            comments = filterVisibleInteractionComments(content.comments)
            updatePinnedCommentIDs()
            commentErrorMessage = content.commentErrorMessage
            await authorProfileStore.loadMissingAuthors(for: comments)
            syncAuthorDisplays()
            let resolvedPostUserState = await fetchedPostUserState
            post = content.post
            postUserState = resolvedPostUserState
            visibleCommentCount = content.visibleCommentCount
            postInteractionStore.seed(
                post: content.post,
                visibleCommentCount: content.visibleCommentCount,
                userState: resolvedPostUserState
            )
            loadedKey = "\(brandID.value)|\(seasonID.value)|\(postID.value)"
        } catch {
            post = nil
            postUserState = nil
            comments = []
            updatePinnedCommentIDs()
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

    private func ensureInteractionPinScope() {
        guard interactionPinScope == nil else { return }
        interactionPinScope = postInteractionStore.pinScope(postIDs: [postID], commentIDs: [])
    }

    private func bindInteractionStore() {
        if let state = postInteractionStore.state(for: postID) {
            applyInteractionState(state)
        }

        let postID = postID
        let postInteractionStore = postInteractionStore
        postStateInvalidationTask = Task { [weak self, postInteractionStore, postID] in
            let stream = postInteractionStore.postStateInvalidationStream(for: [postID])
            for await invalidatedPostID in stream {
                guard invalidatedPostID == postID,
                      let state = postInteractionStore.state(for: postID) else { continue }
                self?.applyInteractionState(state)
            }
        }

        let commentInteractionStore = commentInteractionStore
        representativeCommentInvalidationTask = Task { [weak self, commentInteractionStore, postID] in
            let stream = commentInteractionStore.representativeCommentInvalidationStream(for: postID)
            for await _ in stream {
                await self?.refreshRepresentativeComment()
            }
        }
    }

    private func applyInteractionState(_ state: LookbookPostInteractionState) {
        if var post {
            post.metrics = state.metrics
            self.post = post
        }
        visibleCommentCount = state.visibleCommentCount
        postUserState = state.userState
    }

    private func applyCommentState(_ state: CommentInteractionState) {
        if state.isHidden {
            let shouldRefreshRepresentativeComment = comments.contains { $0.id == state.commentID }
            comments.removeAll { $0.id == state.commentID }
            updatePinnedCommentIDs()
            if shouldRefreshRepresentativeComment {
                Task { [weak self] in
                    await self?.refreshRepresentativeComment()
                }
            }
            return
        }

        if let replyCount = state.replyCount {
            comments = comments.map { comment in
                guard comment.id == state.commentID else { return comment }
                var updatedComment = comment
                updatedComment.replyCount = replyCount
                return updatedComment
            }
        }
        if let likeCount = state.likeCount {
            comments = comments.map { comment in
                guard comment.id == state.commentID else { return comment }
                var updatedComment = comment
                updatedComment.likeCount = likeCount
                return updatedComment
            }
        }
    }

    private func filterVisibleInteractionComments(_ comments: [Comment]) -> [Comment] {
        comments.filter { commentInteractionStore.isCommentHidden($0.id) == false }
    }

    private func updatePinnedCommentIDs() {
        let nextCommentIDs = Set(comments.map(\.id))
        guard nextCommentIDs != pinnedCommentIDs else { return }

        let removedCommentIDs = pinnedCommentIDs.subtracting(nextCommentIDs)
        let addedCommentIDs = nextCommentIDs.subtracting(pinnedCommentIDs)

        for commentID in removedCommentIDs {
            commentPinScopes[commentID]?.invalidate()
            commentPinScopes.removeValue(forKey: commentID)
        }

        for commentID in addedCommentIDs {
            commentPinScopes[commentID] = commentInteractionStore.pinScope(postIDs: [], commentIDs: [commentID])
        }
        pinnedCommentIDs = nextCommentIDs
        bindCommentStateInvalidationStream(for: nextCommentIDs)
    }

    private func bindCommentStateInvalidationStream(for commentIDs: Set<CommentID>) {
        commentStateInvalidationTask?.cancel()
        guard commentIDs.isEmpty == false else {
            commentStateInvalidationTask = nil
            return
        }

        let commentInteractionStore = commentInteractionStore
        commentStateInvalidationTask = Task { @MainActor [weak self, commentInteractionStore, commentIDs] in
            let stream = commentInteractionStore.commentStateInvalidationStream(for: commentIDs)
            for commentID in commentIDs {
                guard let state = commentInteractionStore.commentState(for: commentID) else { continue }
                self?.applyCommentState(state)
            }

            for await commentID in stream {
                guard let state = commentInteractionStore.commentState(for: commentID) else { continue }
                self?.applyCommentState(state)
            }
        }
    }

    private func loadHiddenUserIDs() async -> Set<UserID> {
        guard let currentUserID else { return [] }
        do {
            return try await loadHiddenUserIDsUseCase.execute(currentUserID: currentUserID)
        } catch {
            return []
        }
    }

    private func engagementInput(userID: UserID) -> PostEngagementInteractionInput {
        PostEngagementInteractionInput(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: userID,
            currentUserState: postUserState,
            currentMetrics: post?.metrics
        )
    }

    private var currentUserID: UserID? {
        currentUserIDProvider.currentUserID
    }
}
