//
//  PostCommentRepliesViewModel.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import Foundation

@MainActor
final class PostCommentRepliesViewModel: ObservableObject {
    @Published private(set) var replies: [Comment] = []
    @Published private(set) var authorDisplays: [UserID: CommentAuthorDisplay] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var isSubmittingReply: Bool = false
    @Published private(set) var isPerformingCommentAction: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var submissionErrorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published var draftMessage: String = ""

    @Published private(set) var parentComment: Comment

    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    private let useCase: any LoadCommentRepliesUseCaseProtocol
    private let createUseCase: any CreateCommentReplyUseCaseProtocol
    private let deleteUseCase: any DeleteCommentUseCaseProtocol
    private let reportUseCase: any ReportCommentUseCaseProtocol
    private let blockUseCase: any BlockUserUseCaseProtocol
    private let authorProfileStore: CommentAuthorProfileStore
    private let avatarImageManager: ChatAvatarImageManaging
    private let pageSize: Int
    private let avatarPrefetchLimit: Int
    private let avatarThumbnailMaxBytes: Int

    private var nextCursor: PageCursor?
    private var loadedKey: String?
    private var isRequestingPage: Bool = false
    private var prefetchedAvatarPaths: Set<String> = []

    var hasMoreReplies: Bool {
        nextCursor != nil
    }

    var canSubmitReply: Bool {
        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            isSubmittingReply == false
    }

    var currentBrandID: BrandID {
        brandID
    }

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentComment: Comment,
        useCase: any LoadCommentRepliesUseCaseProtocol,
        createUseCase: any CreateCommentReplyUseCaseProtocol,
        deleteUseCase: any DeleteCommentUseCaseProtocol,
        reportUseCase: any ReportCommentUseCaseProtocol,
        blockUseCase: any BlockUserUseCaseProtocol,
        authorProfileStore: CommentAuthorProfileStore? = nil,
        avatarImageManager: ChatAvatarImageManaging = AvatarImageService.shared,
        pageSize: Int = 30,
        avatarPrefetchLimit: Int = 16,
        avatarThumbnailMaxBytes: Int = 3 * 1024 * 1024
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.parentComment = parentComment
        self.useCase = useCase
        self.createUseCase = createUseCase
        self.deleteUseCase = deleteUseCase
        self.reportUseCase = reportUseCase
        self.blockUseCase = blockUseCase
        self.authorProfileStore = authorProfileStore ?? CommentAuthorProfileStore()
        self.avatarImageManager = avatarImageManager
        self.pageSize = pageSize
        self.avatarPrefetchLimit = avatarPrefetchLimit
        self.avatarThumbnailMaxBytes = avatarThumbnailMaxBytes
    }

    func loadIfNeeded() async {
        let key = stateKey()
        guard loadedKey != key else { return }
        await loadPage(reset: true)
    }

    func refresh() async {
        loadedKey = nil
        await loadPage(reset: true)
    }

    func loadNextPage() async {
        guard hasMoreReplies else { return }
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
            removeComments(by: comment.userID)
            return block
        } catch {
            actionErrorMessage = "사용자를 차단하지 못했습니다."
            return nil
        }
    }

    func prefetchAuthorAvatars(around commentID: CommentID) {
        let comments = [parentComment] + replies
        guard let index = comments.firstIndex(where: { $0.id == commentID }) else { return }

        let upperBound = min(comments.count, index + avatarPrefetchLimit)
        let paths = comments[index..<upperBound]
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
    func submitReply() async -> CommentMutationResult? {
        guard isSubmittingReply == false else { return nil }

        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isEmpty == false else {
            submissionErrorMessage = CommentSubmissionError.emptyMessage.localizedDescription
            return nil
        }

        isSubmittingReply = true
        submissionErrorMessage = nil
        defer {
            isSubmittingReply = false
        }

        do {
            let result = try await createUseCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentCommentID: parentComment.id,
                message: message
            )
            parentComment.replyCount = result.replyCount
            draftMessage = ""
            authorProfileStore.seedCurrentUserProfileIfPossible()
            syncAuthorDisplays()
            loadedKey = nil
            await loadPage(reset: true)
            return result
        } catch {
            submissionErrorMessage = "답글을 등록하지 못했습니다."
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
            await authorProfileStore.loadMissingAuthors(for: [parentComment])
            syncAuthorDisplays()
            let page = try await useCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentCommentID: parentComment.id,
                page: PageRequest(
                    size: pageSize,
                    cursor: reset ? nil : nextCursor
                )
            )

            nextCursor = page.nextCursor
            if reset {
                replies = page.items
                loadedKey = stateKey()
            } else {
                replies.append(contentsOf: page.items)
            }
            await authorProfileStore.loadMissingAuthors(for: page.items)
            syncAuthorDisplays()
        } catch {
            errorMessage = "답글을 불러오지 못했습니다."
        }
    }

    private func syncAuthorDisplays() {
        authorDisplays = authorProfileStore.authorDisplays
    }

    private func applyDeletion(_ result: CommentDeletionResult) {
        if result.commentID == parentComment.id {
            return
        }

        replies.removeAll { $0.id == result.commentID }
        parentComment.replyCount = max(0, parentComment.replyCount - max(1, result.deletedCommentCount))
    }

    private func removeComments(by userID: UserID) {
        replies.removeAll { $0.userID == userID }
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

    private func stateKey() -> String {
        "\(brandID.value)|\(seasonID.value)|\(postID.value)|\(parentComment.id.value)"
    }
}
