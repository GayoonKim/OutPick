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
    @Published private(set) var errorMessage: String?
    @Published private(set) var submissionErrorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published var draftMessage: String = ""

    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    private let useCase: any LoadPostCommentsUseCaseProtocol
    private let createUseCase: any CreatePostCommentUseCaseProtocol
    private let deleteUseCase: any DeleteCommentUseCaseProtocol
    private let reportUseCase: any ReportCommentUseCaseProtocol
    private let blockUseCase: any BlockUserUseCaseProtocol
    private let loadHiddenUserIDsUseCase: any LoadHiddenCommentUserIDsUseCaseProtocol
    private let filterHiddenAuthorsUseCase: FilterHiddenCommentAuthorsUseCase
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
        deleteUseCase: any DeleteCommentUseCaseProtocol,
        reportUseCase: any ReportCommentUseCaseProtocol,
        blockUseCase: any BlockUserUseCaseProtocol,
        loadHiddenUserIDsUseCase: any LoadHiddenCommentUserIDsUseCaseProtocol,
        filterHiddenAuthorsUseCase: FilterHiddenCommentAuthorsUseCase,
        authorProfileStore: CommentAuthorProfileStore? = nil,
        avatarImageManager: ChatAvatarImageManaging = AvatarImageService.shared,
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
        self.deleteUseCase = deleteUseCase
        self.reportUseCase = reportUseCase
        self.blockUseCase = blockUseCase
        self.loadHiddenUserIDsUseCase = loadHiddenUserIDsUseCase
        self.filterHiddenAuthorsUseCase = filterHiddenAuthorsUseCase
        self.authorProfileStore = authorProfileStore ?? CommentAuthorProfileStore()
        self.avatarImageManager = avatarImageManager
        self.selectedSort = initialSort
        self.pageSize = pageSize
        self.avatarPrefetchLimit = avatarPrefetchLimit
        self.avatarThumbnailMaxBytes = avatarThumbnailMaxBytes
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

    func clearActionError() {
        actionErrorMessage = nil
    }

    func canDelete(_ comment: Comment, isBrandWritable: Bool) -> Bool {
        isCurrentUser(comment.userID) || isBrandWritable
    }

    func canReportOrBlock(_ comment: Comment) -> Bool {
        isCurrentUser(comment.userID) == false
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
            applyDeletion(result)
            return result
        } catch {
            actionErrorMessage = "댓글을 삭제하지 못했습니다."
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
            actionErrorMessage = "댓글을 신고하지 못했습니다."
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
            removeComments(by: comment.userID)
            return block
        } catch {
            actionErrorMessage = "사용자를 차단하지 못했습니다."
            return nil
        }
    }

    func prefetchAuthorAvatars(around commentID: CommentID) {
        let items = commentFeedComments
        guard let index = items.firstIndex(where: { $0.id == commentID }) else { return }

        let upperBound = min(items.count, index + avatarPrefetchLimit)
        let paths = items[index..<upperBound]
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
            authorProfileStore.seedCurrentUserProfileIfPossible()
            syncAuthorDisplays()
            loadedKey = nil
            await loadPage(reset: true)
            return result
        } catch {
            submissionErrorMessage = "댓글을 등록하지 못했습니다."
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
                pinnedComments = filterHiddenAuthors(content.pinnedComments, hiddenUserIDs: currentHiddenUserIDs)
                representativeComment = visibleComment(
                    content.representativeComment,
                    hiddenUserIDs: currentHiddenUserIDs
                )
                nextCursor = content.rootComments.nextCursor
                rootComments = filterHiddenAuthors(content.rootComments.items, hiddenUserIDs: currentHiddenUserIDs)
                loadedKey = stateKey(sort: selectedSort)
                await authorProfileStore.loadMissingAuthors(for: commentFeedComments)
                syncAuthorDisplays()
            } else {
                let page = try await useCase.loadRootComments(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID,
                    sort: selectedSort,
                    page: PageRequest(size: pageSize, cursor: nextCursor)
                )
                let excludedIDs = duplicateExcludedIDs()
                let visibleItems = filterHiddenAuthors(
                    page.items,
                    hiddenUserIDs: currentHiddenUserIDs
                ).filter {
                    excludedIDs.contains($0.id) == false
                }
                nextCursor = page.nextCursor
                rootComments.append(contentsOf: visibleItems)
                await authorProfileStore.loadMissingAuthors(for: visibleItems)
                syncAuthorDisplays()
            }
        } catch {
            errorMessage = "댓글을 불러오지 못했습니다."
        }
    }

    private func syncAuthorDisplays() {
        authorDisplays = authorProfileStore.authorDisplays
    }

    private func applyDeletion(_ result: CommentDeletionResult) {
        pinnedComments.removeAll { $0.id == result.commentID }
        if representativeComment?.id == result.commentID {
            representativeComment = nil
        }
        rootComments.removeAll { $0.id == result.commentID }
    }

    private func removeComments(by userID: UserID) {
        pinnedComments.removeAll { $0.userID == userID }
        if representativeComment?.userID == userID {
            representativeComment = nil
        }
        rootComments.removeAll { $0.userID == userID }
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
            print(#function, "%%%%% 차단 + 차단된 사용자 %%%%%", hiddenUserIDs)
        } catch {
            print(#function, "%%%%% 차단 사용자 없음. %%%%%")
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
        return hiddenUserIDs.contains(comment.userID) ? nil : comment
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
        let identityKey = LoginManager.shared.getAuthIdentityKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard identityKey.isEmpty == false else { return nil }
        return UserID(value: identityKey)
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
