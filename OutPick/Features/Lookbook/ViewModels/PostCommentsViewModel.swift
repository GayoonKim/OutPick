//
//  PostCommentsViewModel.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import Foundation

@MainActor
final class PostCommentsViewModel: ObservableObject {
    @Published private(set) var pinnedComments: [Comment] = []
    @Published private(set) var representativeComment: Comment?
    @Published private(set) var rootComments: [Comment] = []
    @Published private(set) var authorDisplays: [UserID: CommentAuthorDisplay] = [:]
    @Published private(set) var selectedSort: CommentSortOption
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var isSubmittingComment: Bool = false
    @Published private(set) var isPerformingCommentAction: Bool = false
    @Published private(set) var mutatingLikeCommentIDs: Set<CommentID> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var submissionErrorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published var draftMessage: String = ""

    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    private let useCase: any LoadPostCommentsUseCaseProtocol
    private let createUseCase: any CreatePostCommentUseCaseProtocol
    private let commentEngagementInteractionUseCase: CommentEngagementInteractionUseCase
    private let deleteUseCase: any DeleteCommentUseCaseProtocol
    private let reportUseCase: any ReportCommentUseCaseProtocol
    private let blockUseCase: any BlockUserUseCaseProtocol
    private let commentUserStateRepository: any CommentUserStateRepositoryProtocol
    private let loadHiddenUserIDsUseCase: any LoadHiddenCommentUserIDsUseCaseProtocol
    private let filterHiddenAuthorsUseCase: FilterHiddenCommentAuthorsUseCase
    private let commentInteractionStore: any CommentInteractionManaging
    private let currentUserIDProvider: any CurrentUserIDProviding
    private let authorProfileStore: CommentAuthorProfileStore
    private let avatarImageManager: ChatAvatarImageManaging
    private let pageSize: Int
    private let avatarPrefetchLimit: Int
    private let avatarThumbnailMaxBytes: Int

    private var nextCursor: PageCursor?
    private var loadedKey: String?
    private var isRequestingPage: Bool = false
    private var prefetchedAvatarPaths: Set<String> = []
    private var hiddenUserIDs: Set<UserID> = []
    private var didLoadHiddenUserIDs: Bool = false
    private var pinnedCommentIDs: Set<CommentID> = []
    private var commentPinScopes: [CommentID: InteractionPinScope] = [:]
    private var commentStateInvalidationTask: Task<Void, Never>?

    var hasMoreRootComments: Bool {
        nextCursor != nil
    }

    var canSubmitComment: Bool {
        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            isSubmittingComment == false
    }

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostCommentsUseCaseProtocol,
        createUseCase: any CreatePostCommentUseCaseProtocol,
        commentEngagementInteractionUseCase: CommentEngagementInteractionUseCase,
        deleteUseCase: any DeleteCommentUseCaseProtocol,
        reportUseCase: any ReportCommentUseCaseProtocol,
        blockUseCase: any BlockUserUseCaseProtocol,
        commentUserStateRepository: any CommentUserStateRepositoryProtocol,
        loadHiddenUserIDsUseCase: any LoadHiddenCommentUserIDsUseCaseProtocol,
        filterHiddenAuthorsUseCase: FilterHiddenCommentAuthorsUseCase,
        commentInteractionStore: any CommentInteractionManaging,
        currentUserIDProvider: any CurrentUserIDProviding,
        authorProfileStore: CommentAuthorProfileStore? = nil,
        avatarImageManager: ChatAvatarImageManaging,
        initialSort: CommentSortOption = .latest,
        pageSize: Int = 30,
        avatarPrefetchLimit: Int = 16,
        avatarThumbnailMaxBytes: Int = 3 * 1024 * 1024
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.useCase = useCase
        self.createUseCase = createUseCase
        self.commentEngagementInteractionUseCase = commentEngagementInteractionUseCase
        self.deleteUseCase = deleteUseCase
        self.reportUseCase = reportUseCase
        self.blockUseCase = blockUseCase
        self.commentUserStateRepository = commentUserStateRepository
        self.loadHiddenUserIDsUseCase = loadHiddenUserIDsUseCase
        self.filterHiddenAuthorsUseCase = filterHiddenAuthorsUseCase
        self.commentInteractionStore = commentInteractionStore
        self.currentUserIDProvider = currentUserIDProvider
        self.authorProfileStore = authorProfileStore ?? CommentAuthorProfileStore(
            currentUserIDProvider: currentUserIDProvider
        )
        self.avatarImageManager = avatarImageManager
        self.selectedSort = initialSort
        self.pageSize = pageSize
        self.avatarPrefetchLimit = avatarPrefetchLimit
        self.avatarThumbnailMaxBytes = avatarThumbnailMaxBytes
        bindInteractionStore()
    }

    deinit {
        commentStateInvalidationTask?.cancel()
    }

    func loadIfNeeded() async {
        let key = stateKey(sort: selectedSort)
        guard loadedKey != key else { return }
        await loadPage(reset: true)
    }

    func refresh() async {
        loadedKey = nil
        didLoadHiddenUserIDs = false
        await loadPage(reset: true)
    }

    func selectSort(_ sort: CommentSortOption) async {
        guard selectedSort != sort else { return }
        selectedSort = sort
        loadedKey = nil
        await loadPage(reset: true)
    }

    func loadNextPage() async {
        guard hasMoreRootComments else { return }
        await loadPage(reset: false)
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

    func isCommentLiked(_ comment: Comment) -> Bool {
        commentInteractionStore.isCommentLiked(comment, userID: currentUserID)
    }

    func isMutatingLike(_ comment: Comment) -> Bool {
        mutatingLikeCommentIDs.contains(comment.id)
    }

    func clearActionError() {
        actionErrorMessage = nil
    }

    func clearSubmissionError() {
        submissionErrorMessage = nil
    }

    func canDelete(_ comment: Comment, isBrandWritable: Bool) -> Bool {
        isCurrentUser(comment.userID) || isBrandWritable
    }

    func canReportOrBlock(_ comment: Comment) -> Bool {
        isCurrentUser(comment.userID) == false
    }

    @discardableResult
    func toggleLike(_ comment: Comment) async -> Bool {
        guard let userID = currentUserID else {
            actionErrorMessage = "로그인이 필요합니다."
            return false
        }

        actionErrorMessage = nil
        let outcome = await commentEngagementInteractionUseCase.toggleLike(
            input: CommentEngagementInteractionInput(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                comment: comment,
                userID: userID,
                currentLiked: isCommentLiked(comment),
                currentLikeCount: displayLikeCount(for: comment)
            ),
            onMutationStateChanged: { [weak self] commentID, isMutating in
                guard let self else { return }
                var nextMutatingIDs = self.mutatingLikeCommentIDs
                if isMutating {
                    nextMutatingIDs.insert(commentID)
                } else {
                    nextMutatingIDs.remove(commentID)
                }
                self.mutatingLikeCommentIDs = nextMutatingIDs
            }
        )
        actionErrorMessage = outcome.errorMessage
        guard outcome.errorMessage == nil else { return false }
        if comment.isRootComment {
            await refreshRepresentativeComment()
        }
        return true
    }

    @discardableResult
    func deleteComment(_ comment: Comment) async -> CommentDeletionResult? {
        guard isPerformingCommentAction == false else { return nil }

        isPerformingCommentAction = true
        actionErrorMessage = nil
        defer {
            isPerformingCommentAction = false
        }

        do {
            let result = try await deleteUseCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                commentID: comment.id,
                reason: nil
            )
            commentInteractionStore.applyCommentDeletion(result)
            return result
        } catch {
            actionErrorMessage = "댓글을 삭제하지 못했어요."
            return nil
        }
    }

    @discardableResult
    func reportComment(
        _ comment: Comment,
        author: CommentAuthorDisplay,
        reason: CommentReportReason,
        detail: String?
    ) async -> CommentReport? {
        guard isPerformingCommentAction == false,
              let reporterUserID = currentUserID,
              canReportOrBlock(comment) else {
            return nil
        }

        isPerformingCommentAction = true
        actionErrorMessage = nil
        defer {
            isPerformingCommentAction = false
        }

        do {
            return try await reportUseCase.execute(
                reporterUserID: reporterUserID,
                target: reportTarget(for: comment, author: author),
                reason: reason,
                detail: detail
            )
        } catch {
            actionErrorMessage = "댓글을 신고하지 못했어요."
            return nil
        }
    }

    @discardableResult
    func blockAuthor(
        of comment: Comment,
        author: CommentAuthorDisplay
    ) async -> UserBlock? {
        guard isPerformingCommentAction == false,
              let blockerUserID = currentUserID,
              canReportOrBlock(comment) else {
            return nil
        }

        isPerformingCommentAction = true
        actionErrorMessage = nil
        defer {
            isPerformingCommentAction = false
        }

        do {
            let block = try await blockUseCase.execute(
                blockerUserID: blockerUserID,
                blockedUserID: comment.userID,
                blockedUserNicknameSnapshot: author.nickname,
                source: comment.parentCommentID == nil ? .comment : .reply
            )
            hiddenUserIDs.insert(comment.userID)
            didLoadHiddenUserIDs = true
            let hiddenCommentIDs = Set(commentFeedComments.filter { $0.userID == comment.userID }.map(\.id))
            commentInteractionStore.hideCommentIDs(hiddenCommentIDs)
            return block
        } catch {
            actionErrorMessage = "사용자를 차단하지 못했어요."
            return nil
        }
    }

    func prefetchAuthorAvatars(around commentID: CommentID) {
        let items = commentFeedComments
        guard let index = items.firstIndex(where: { $0.id == commentID }) else { return }

        let upperBound = min(items.count, index + avatarPrefetchLimit)
        prefetchAuthorAvatars(for: Array(items[index..<upperBound]))
    }

    func prefetchInitialAuthorAvatars() {
        prefetchAuthorAvatars(for: Array(commentFeedComments.prefix(avatarPrefetchLimit)))
    }

    private func prefetchAuthorAvatars(for comments: [Comment]) {
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

    @discardableResult
    func submitComment() async -> CommentMutationResult? {
        guard isSubmittingComment == false else { return nil }

        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isEmpty == false else {
            submissionErrorMessage = CommentSubmissionError.emptyMessage.localizedDescription
            return nil
        }

        isSubmittingComment = true
        submissionErrorMessage = nil
        defer {
            isSubmittingComment = false
        }

        do {
            let result = try await createUseCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                message: message
            )
            draftMessage = ""
            commentInteractionStore.applyCommentMutation(result)
            authorProfileStore.seedCurrentUserProfileIfPossible()
            syncAuthorDisplays()
            loadedKey = nil
            await loadPage(reset: true)
            return result
        } catch {
            submissionErrorMessage = "댓글을 등록하지 못했어요."
            return nil
        }
    }

    private func loadPage(reset: Bool) async {
        guard isRequestingPage == false else { return }
        isRequestingPage = true
        if reset {
            isLoading = true
            errorMessage = nil
        } else {
            isLoadingMore = true
        }
        defer {
            isRequestingPage = false
            isLoading = false
            isLoadingMore = false
        }

        do {
            let currentHiddenUserIDs = await loadHiddenUserIDsIfNeeded(force: reset)
            if reset {
                let content = try await useCase.execute(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID,
                    sort: selectedSort,
                    page: PageRequest(size: pageSize, cursor: nil)
                )
                pinnedComments = filterVisibleComments(
                    content.pinnedComments,
                    hiddenUserIDs: currentHiddenUserIDs
                )
                representativeComment = visibleComment(
                    content.representativeComment,
                    hiddenUserIDs: currentHiddenUserIDs
                )
                nextCursor = content.rootComments.nextCursor
                rootComments = filterVisibleComments(
                    content.rootComments.items,
                    hiddenUserIDs: currentHiddenUserIDs
                )
                loadedKey = stateKey(sort: selectedSort)
                await authorProfileStore.loadMissingAuthors(for: commentFeedComments)
                syncAuthorDisplays()
                await seedCommentLikeStates(for: commentFeedComments)
                updatePinnedCommentIDs()
                prefetchInitialAuthorAvatars()
            } else {
                let page = try await useCase.loadRootComments(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID,
                    sort: selectedSort,
                    page: PageRequest(size: pageSize, cursor: nextCursor)
                )
                let excludedIDs = duplicateExcludedIDs()
                let visibleItems = filterVisibleComments(
                    page.items,
                    hiddenUserIDs: currentHiddenUserIDs
                ).filter {
                    excludedIDs.contains($0.id) == false
                }
                nextCursor = page.nextCursor
                rootComments.append(contentsOf: visibleItems)
                await authorProfileStore.loadMissingAuthors(for: visibleItems)
                syncAuthorDisplays()
                await seedCommentLikeStates(for: visibleItems)
                updatePinnedCommentIDs()
            }
        } catch {
            errorMessage = "댓글을 불러오지 못했습니다."
        }
    }

    private func syncAuthorDisplays() {
        authorDisplays = authorProfileStore.authorDisplays
    }

    private func refreshRepresentativeComment() async {
        do {
            let previousRepresentativeComment = representativeComment
            let nextRepresentativeComment = try await useCase.loadRepresentativeComment(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID
            )
            reconcileRepresentativeComment(
                previous: previousRepresentativeComment,
                next: visibleComment(nextRepresentativeComment, hiddenUserIDs: hiddenUserIDs)
            )
        } catch {
            actionErrorMessage = "대표 댓글을 갱신하지 못했어요."
        }
    }

    private func reconcileRepresentativeComment(
        previous: Comment?,
        next: Comment?
    ) {
        let previousID = previous?.id
        let nextID = next?.id

        if let previous,
           previousID != nextID,
           previous.isPinned == false,
           hiddenUserIDs.contains(previous.userID) == false,
           commentInteractionStore.isCommentHidden(previous.id) == false,
           rootComments.contains(where: { $0.id == previous.id }) == false {
            rootComments.append(previous)
        }

        representativeComment = next

        if let nextID {
            rootComments.removeAll { $0.id == nextID }
        }
        rootComments = sortedRootComments(rootComments)
        updatePinnedCommentIDs()
    }

    private func sortedRootComments(_ comments: [Comment]) -> [Comment] {
        switch selectedSort {
        case .latest:
            return comments.sorted { lhs, rhs in
                lhs.createdAt > rhs.createdAt
            }
        case .popular:
            return comments.sorted { lhs, rhs in
                if lhs.likeCount == rhs.likeCount {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.likeCount > rhs.likeCount
            }
        }
    }

    private func bindInteractionStore() {
    }

    private func applyCommentState(_ state: CommentInteractionState) {
        if state.isHidden {
            hideComment(state.commentID)
            return
        }

        if let replyCount = state.replyCount {
            updateReplyCount(replyCount, for: state.commentID)
        }
        if let likeCount = state.likeCount {
            updateLikeCount(likeCount, for: state.commentID)
        }
    }

    private func updateReplyCount(
        _ replyCount: Int,
        for commentID: CommentID
    ) {
        pinnedComments = pinnedComments.map { comment in
            updatedReplyCountComment(comment, commentID: commentID, replyCount: replyCount)
        }
        if let representativeComment {
            self.representativeComment = updatedReplyCountComment(
                representativeComment,
                commentID: commentID,
                replyCount: replyCount
            )
        }
        rootComments = rootComments.map { comment in
            updatedReplyCountComment(comment, commentID: commentID, replyCount: replyCount)
        }
    }

    private func updatedReplyCountComment(
        _ comment: Comment,
        commentID: CommentID,
        replyCount: Int
    ) -> Comment {
        guard comment.id == commentID else { return comment }
        var updatedComment = comment
        updatedComment.replyCount = replyCount
        return updatedComment
    }

    private func updateLikeCount(
        _ likeCount: Int,
        for commentID: CommentID
    ) {
        pinnedComments = pinnedComments.map { comment in
            updatedLikeCountComment(comment, commentID: commentID, likeCount: likeCount)
        }
        if let representativeComment {
            self.representativeComment = updatedLikeCountComment(
                representativeComment,
                commentID: commentID,
                likeCount: likeCount
            )
        }
        rootComments = rootComments.map { comment in
            updatedLikeCountComment(comment, commentID: commentID, likeCount: likeCount)
        }
    }

    private func updatedLikeCountComment(
        _ comment: Comment,
        commentID: CommentID,
        likeCount: Int
    ) -> Comment {
        guard comment.id == commentID else { return comment }
        var updatedComment = comment
        updatedComment.likeCount = likeCount
        return updatedComment
    }

    private func hideComment(_ commentID: CommentID) {
        pinnedComments.removeAll { $0.id == commentID }
        if representativeComment?.id == commentID {
            representativeComment = nil
        }
        rootComments.removeAll { $0.id == commentID }
        updatePinnedCommentIDs()
    }

    private func loadHiddenUserIDsIfNeeded(force: Bool) async -> Set<UserID> {
        if force {
            didLoadHiddenUserIDs = false
        }

        guard didLoadHiddenUserIDs == false else {
            return hiddenUserIDs
        }
        guard let currentUserID else {
            hiddenUserIDs = []
            didLoadHiddenUserIDs = true
            return []
        }

        do {
            hiddenUserIDs = try await loadHiddenUserIDsUseCase.execute(currentUserID: currentUserID)
        } catch {
            hiddenUserIDs = []
        }
        didLoadHiddenUserIDs = true
        return hiddenUserIDs
    }

    private func filterHiddenAuthors(
        _ comments: [Comment],
        hiddenUserIDs: Set<UserID>
    ) -> [Comment] {
        filterHiddenAuthorsUseCase.execute(
            comments: comments,
            hiddenUserIDs: hiddenUserIDs
        )
    }

    private func visibleComment(
        _ comment: Comment?,
        hiddenUserIDs: Set<UserID>
    ) -> Comment? {
        guard let comment else { return nil }
        guard hiddenUserIDs.contains(comment.userID) == false,
              commentInteractionStore.isCommentHidden(comment.id) == false else {
            return nil
        }
        return comment
    }

    private func filterVisibleComments(
        _ comments: [Comment],
        hiddenUserIDs: Set<UserID>
    ) -> [Comment] {
        filterHiddenAuthors(comments, hiddenUserIDs: hiddenUserIDs)
            .filter { commentInteractionStore.isCommentHidden($0.id) == false }
    }

    private func seedCommentLikeStates(for comments: [Comment]) async {
        guard let currentUserID,
              comments.isEmpty == false else {
            return
        }

        do {
            let states = try await commentUserStateRepository.fetchCommentUserStates(
                userID: currentUserID,
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                commentIDs: comments.map(\.id)
            )
            commentInteractionStore.seedCommentLikeStates(
                comments: comments,
                userStates: states,
                userID: currentUserID
            )
        } catch {
            actionErrorMessage = "댓글 좋아요 상태를 불러오지 못했어요."
        }
    }

    private func reportTarget(
        for comment: Comment,
        author: CommentAuthorDisplay
    ) -> CommentReportTarget {
        CommentReportTarget(
            targetType: comment.parentCommentID == nil ? .comment : .reply,
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: comment.id,
            parentCommentID: comment.parentCommentID,
            authorID: comment.userID,
            contentSnapshot: comment.message,
            authorNicknameSnapshot: author.nickname
        )
    }

    private func isCurrentUser(_ userID: UserID) -> Bool {
        currentUserID == userID
    }

    private var currentUserID: UserID? {
        currentUserIDProvider.currentUserID
    }

    private func duplicateExcludedIDs() -> Set<CommentID> {
        var ids = Set(pinnedComments.map(\.id))
        if let representativeComment {
            ids.insert(representativeComment.id)
        }
        return ids
    }

    private func stateKey(sort: CommentSortOption) -> String {
        "\(brandID.value)|\(seasonID.value)|\(postID.value)|\(sort.rawValue)"
    }

    private func updatePinnedCommentIDs() {
        let nextCommentIDs = Set(commentFeedComments.map(\.id))
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

    private var commentFeedComments: [Comment] {
        var comments = pinnedComments

        if let representativeComment,
           comments.contains(where: { $0.id == representativeComment.id }) == false {
            comments.append(representativeComment)
        }

        comments.append(contentsOf: rootComments)
        return comments
    }
}
