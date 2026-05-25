//
//  LookbookDebugFailureInjectionStoreTests.swift
//  OutPickTests
//
//  Created by Codex on 5/13/26.
//

import Foundation
import Testing
@testable import OutPick

struct LookbookDebugFailureInjectionStoreTests {
    @Test func launchArgumentsEnableMatchingFailureOperations() {
        let store = LookbookDebugFailureInjectionStore()

        LookbookDebugFailureLaunchArguments.apply(
            to: store,
            arguments: [
                "OutPick",
                LookbookDebugFailureLaunchArguments.toggleLike,
                LookbookDebugFailureLaunchArguments.toggleBrandLike,
                LookbookDebugFailureLaunchArguments.toggleCommentLike,
                LookbookDebugFailureLaunchArguments.createComment,
                LookbookDebugFailureLaunchArguments.createReply,
                LookbookDebugFailureLaunchArguments.reportComment,
                LookbookDebugFailureLaunchArguments.blockUser
            ]
        )

        #expect(store.isFailureEnabled(for: .toggleLike) == true)
        #expect(store.isFailureEnabled(for: .toggleSave) == false)
        #expect(store.isFailureEnabled(for: .toggleBrandLike) == true)
        #expect(store.isFailureEnabled(for: .toggleCommentLike) == true)
        #expect(store.isFailureEnabled(for: .createComment) == true)
        #expect(store.isFailureEnabled(for: .createReply) == true)
        #expect(store.isFailureEnabled(for: .deleteComment) == false)
        #expect(store.isFailureEnabled(for: .reportComment) == true)
        #expect(store.isFailureEnabled(for: .blockUser) == true)
    }

    @Test func storeTogglesFailureByOperation() throws {
        let store = LookbookDebugFailureInjectionStore()

        #expect(store.isFailureEnabled(for: .createComment) == false)

        store.setFailure(.createComment, isEnabled: true)

        #expect(store.isFailureEnabled(for: .createComment) == true)
        #expect(store.isFailureEnabled(for: .createReply) == false)

        do {
            try store.throwIfNeeded(.createComment)
            #expect(Bool(false))
        } catch LookbookDebugFailureInjectionError.injected(let operation) {
            #expect(operation == .createComment)
        }

        store.clear()

        #expect(store.isFailureEnabled(for: .createComment) == false)
    }

    @Test func commentWritingFailuresThrowBeforeRepositoryCall() async {
        let store = LookbookDebugFailureInjectionStore()
        let repository = CommentWritingRepositorySpy()
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let postID = PostID(value: "post-1")
        let commentID = CommentID(value: "comment-1")

        store.setFailure(.createComment, isEnabled: true)
        await expectInjectedFailure(.createComment) {
            try await CreatePostCommentUseCase(
                repository: repository,
                debugFailureInjectionStore: store
            ).execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                message: " 댓글 "
            )
        }

        store.setFailure(.createReply, isEnabled: true)
        await expectInjectedFailure(.createReply) {
            try await CreateCommentReplyUseCase(
                repository: repository,
                debugFailureInjectionStore: store
            ).execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentCommentID: commentID,
                message: " 답글 "
            )
        }

        store.setFailure(.deleteComment, isEnabled: true)
        await expectInjectedFailure(.deleteComment) {
            try await DeleteCommentUseCase(
                repository: repository,
                debugFailureInjectionStore: store
            ).execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                commentID: commentID,
                reason: " 삭제 "
            )
        }

        #expect(repository.createCommentCallCount == 0)
        #expect(repository.createReplyCallCount == 0)
        #expect(repository.deleteCommentCallCount == 0)
    }

    @Test func commentSafetyFailuresThrowBeforeRepositoryCall() async {
        let store = LookbookDebugFailureInjectionStore()
        let reportRepository = CommentSafetyRepositorySpy()
        let blockRepository = UserBlockRepositorySpy()
        let reporterUserID = UserID(value: "reporter-1")
        let authorID = UserID(value: "author-1")
        let target = makeReportTarget(authorID: authorID)

        store.setFailure(.reportComment, isEnabled: true)
        await expectInjectedFailure(.reportComment) {
            try await ReportCommentUseCase(
                repository: reportRepository,
                debugFailureInjectionStore: store
            ).execute(
                reporterUserID: reporterUserID,
                target: target,
                reason: .spam,
                detail: " 신고 "
            )
        }

        store.setFailure(.blockUser, isEnabled: true)
        await expectInjectedFailure(.blockUser) {
            try await BlockUserUseCase(
                repository: blockRepository,
                debugFailureInjectionStore: store
            ).execute(
                blockerUserID: reporterUserID,
                blockedUserID: authorID,
                blockedUserNicknameSnapshot: " 작성자 ",
                source: .comment
            )
        }

        #expect(reportRepository.reportCallCount == 0)
        #expect(blockRepository.blockCallCount == 0)
    }

    @MainActor
    @Test func engagementFailuresUseExistingErrorPathWithoutRepositoryCall() async {
        let store = LookbookDebugFailureInjectionStore()
        let repository = PostEngagementRepositorySpy()
        let interactionStore = PostInteractionManagingSpy()
        let useCase = PostEngagementInteractionUseCase(
            repository: repository,
            postInteractionStore: interactionStore,
            debugFailureInjectionStore: store
        )
        let input = makeEngagementInput()

        store.setFailure(.toggleLike, isEnabled: true)
        let likeOutcome = await useCase.toggleLike(
            input: input,
            onMutationStateChanged: { _ in }
        )

        #expect(likeOutcome.errorMessage == "좋아요를 반영하지 못했어요.")
        #expect(repository.setLikeCallCount == 0)
        #expect(interactionStore.optimisticLikeCallCount == 1)
        #expect(interactionStore.restoreLikeCallCount == 1)

        store.setFailure(.toggleSave, isEnabled: true)
        let saveOutcome = await useCase.toggleSave(
            input: input,
            onMutationStateChanged: { _ in }
        )

        #expect(saveOutcome.errorMessage == "저장을 반영하지 못했어요.")
        #expect(repository.setSaveCallCount == 0)
        #expect(interactionStore.optimisticSaveCallCount == 1)
        #expect(interactionStore.restoreSaveCallCount == 1)
    }

    @MainActor
    @Test func commentEngagementFailureRestoresOptimisticStateWithoutRepositoryCall() async {
        let store = LookbookDebugFailureInjectionStore()
        let repository = CommentEngagementRepositorySpy()
        let interactionStore = CommentInteractionManagingSpy()
        let useCase = CommentEngagementInteractionUseCase(
            repository: repository,
            commentInteractionStore: interactionStore,
            debugFailureInjectionStore: store
        )
        let comment = makeComment()
        let userID = UserID(value: "user-1")

        store.setFailure(.toggleCommentLike, isEnabled: true)
        let outcome = await useCase.toggleLike(
            input: CommentEngagementInteractionInput(
                brandID: BrandID(value: "brand-1"),
                seasonID: SeasonID(value: "season-1"),
                postID: comment.postID,
                comment: comment,
                userID: userID,
                currentLiked: false,
                currentLikeCount: 3
            ),
            onMutationStateChanged: { _, _ in }
        )

        #expect(outcome.errorMessage == "좋아요를 반영하지 못했어요.")
        #expect(repository.setLikeCallCount == 0)
        #expect(interactionStore.optimisticLikeCallCount == 1)
        #expect(interactionStore.restoreLikeCallCount == 1)
    }

    @MainActor
    @Test func commentEngagementSuccessInvalidatesRepresentativeCommentOnlyForRootComment() async {
        let repository = CommentEngagementRepositorySpy()
        let interactionStore = CommentInteractionManagingSpy()
        let useCase = CommentEngagementInteractionUseCase(
            repository: repository,
            commentInteractionStore: interactionStore
        )
        let rootComment = makeComment(id: CommentID(value: "root-comment"))
        let reply = makeComment(
            id: CommentID(value: "reply-comment"),
            parentCommentID: rootComment.id
        )
        let userID = UserID(value: "user-1")

        _ = await useCase.toggleLike(
            input: CommentEngagementInteractionInput(
                brandID: BrandID(value: "brand-1"),
                seasonID: SeasonID(value: "season-1"),
                postID: rootComment.postID,
                comment: rootComment,
                userID: userID,
                currentLiked: false,
                currentLikeCount: 3
            ),
            onMutationStateChanged: { _, _ in }
        )

        repository.parentCommentID = rootComment.id
        _ = await useCase.toggleLike(
            input: CommentEngagementInteractionInput(
                brandID: BrandID(value: "brand-1"),
                seasonID: SeasonID(value: "season-1"),
                postID: reply.postID,
                comment: reply,
                userID: userID,
                currentLiked: false,
                currentLikeCount: 1
            ),
            onMutationStateChanged: { _, _ in }
        )

        #expect(interactionStore.representativeCommentInvalidationPostIDs == [rootComment.postID])
    }

    private func expectInjectedFailure<T>(
        _ operation: LookbookDebugFailureOperation,
        _ action: () async throws -> T
    ) async {
        do {
            _ = try await action()
            #expect(Bool(false))
        } catch LookbookDebugFailureInjectionError.injected(let injectedOperation) {
            #expect(injectedOperation == operation)
        } catch {
            #expect(Bool(false))
        }
    }

    private func makeReportTarget(authorID: UserID) -> CommentReportTarget {
        CommentReportTarget(
            targetType: .comment,
            brandID: BrandID(value: "brand-1"),
            seasonID: SeasonID(value: "season-1"),
            postID: PostID(value: "post-1"),
            commentID: CommentID(value: "comment-1"),
            parentCommentID: nil,
            authorID: authorID,
            contentSnapshot: "댓글 내용",
            authorNicknameSnapshot: "작성자"
        )
    }

    private func makeEngagementInput() -> PostEngagementInteractionInput {
        let postID = PostID(value: "post-1")
        let userID = UserID(value: "user-1")

        return PostEngagementInteractionInput(
            brandID: BrandID(value: "brand-1"),
            seasonID: SeasonID(value: "season-1"),
            postID: postID,
            userID: userID,
            currentUserState: PostUserState(
                postID: postID,
                userID: userID,
                isLiked: false,
                isSaved: false,
                updatedAt: Date()
            ),
            currentMetrics: PostMetrics(
                likeCount: 3,
                commentCount: 5,
                replacementCount: 0,
                saveCount: 2,
                viewCount: nil
            )
        )
    }

    private func makeComment(
        id: CommentID = CommentID(value: "comment-1"),
        parentCommentID: CommentID? = nil
    ) -> OutPick.Comment {
        OutPick.Comment(
            id: id,
            postID: PostID(value: "post-1"),
            userID: UserID(value: "author-1"),
            message: "댓글",
            createdAt: Date(),
            isDeleted: false,
            likeCount: 3,
            replyCount: 1,
            isPinned: false,
            pinnedAt: nil,
            pinnedBy: nil,
            parentCommentID: parentCommentID,
            attachments: []
        )
    }
}

private final class CommentWritingRepositorySpy: CommentWritingRepositoryProtocol {
    private(set) var createCommentCallCount = 0
    private(set) var createReplyCallCount = 0
    private(set) var deleteCommentCallCount = 0

    func createComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        message: String
    ) async throws -> CommentMutationResult {
        createCommentCallCount += 1
        return CommentMutationResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: CommentID(value: "created-comment"),
            userID: UserID(value: "user-1"),
            parentCommentID: nil,
            commentCount: 1,
            replyCount: 0
        )
    }

    func createReply(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        message: String
    ) async throws -> CommentMutationResult {
        createReplyCallCount += 1
        return CommentMutationResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: CommentID(value: "created-reply"),
            userID: UserID(value: "user-1"),
            parentCommentID: parentCommentID,
            commentCount: 1,
            replyCount: 1
        )
    }

    func deleteComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        reason: String?
    ) async throws -> CommentDeletionResult {
        deleteCommentCallCount += 1
        return CommentDeletionResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: commentID,
            userID: UserID(value: "user-1"),
            parentCommentID: nil,
            targetType: .comment,
            deletedReplyCount: 0,
            deletedCommentCount: 1,
            commentCount: 0,
            replyCount: 0
        )
    }
}

private final class CommentSafetyRepositorySpy: CommentSafetyRepositoryProtocol {
    private(set) var reportCallCount = 0

    func reportComment(
        reporterUserID: UserID,
        target: CommentReportTarget,
        reason: CommentReportReason,
        detail: String?
    ) async throws -> CommentReport {
        reportCallCount += 1
        return CommentReport(
            id: CommentReportID(value: "report-1"),
            reporterUserID: reporterUserID,
            target: target,
            reason: reason,
            detail: detail,
            status: .pending,
            createdAt: Date()
        )
    }
}

private final class UserBlockRepositorySpy: UserBlockRepositoryProtocol {
    private(set) var blockCallCount = 0

    func blockUser(
        blockerUserID: UserID,
        blockedUserID: UserID,
        blockedUserNicknameSnapshot: String?,
        source: UserBlockSource
    ) async throws -> UserBlock {
        blockCallCount += 1
        return UserBlock(
            blockerUserID: blockerUserID,
            blockedUserID: blockedUserID,
            blockedUserNicknameSnapshot: blockedUserNicknameSnapshot,
            source: source,
            createdAt: Date()
        )
    }

    func fetchBlockedUserIDs(
        blockerUserID: UserID
    ) async throws -> Set<UserID> {
        []
    }

    func fetchHiddenCommentUserIDs(
        currentUserID: UserID
    ) async throws -> Set<UserID> {
        []
    }
}

private final class PostEngagementRepositorySpy: PostEngagementRepositoryProtocol {
    private(set) var setLikeCallCount = 0
    private(set) var setSaveCallCount = 0

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isLiked: Bool
    ) async throws -> PostEngagementResult {
        setLikeCallCount += 1
        return makeResult(postID: postID, isLiked: isLiked, isSaved: false)
    }

    func setSave(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isSaved: Bool
    ) async throws -> PostEngagementResult {
        setSaveCallCount += 1
        return makeResult(postID: postID, isLiked: false, isSaved: isSaved)
    }

    private func makeResult(
        postID: PostID,
        isLiked: Bool,
        isSaved: Bool
    ) -> PostEngagementResult {
        PostEngagementResult(
            postID: postID,
            userID: UserID(value: "user-1"),
            isLiked: isLiked,
            isSaved: isSaved,
            metrics: PostMetrics(
                likeCount: isLiked ? 4 : 3,
                commentCount: 5,
                replacementCount: 0,
                saveCount: isSaved ? 3 : 2,
                viewCount: nil
            )
        )
    }
}

private final class CommentEngagementRepositorySpy: CommentEngagementRepositoryProtocol {
    private(set) var setLikeCallCount = 0
    var parentCommentID: CommentID?

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        isLiked: Bool
    ) async throws -> CommentEngagementResult {
        setLikeCallCount += 1
        return CommentEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: commentID,
            userID: UserID(value: "user-1"),
            parentCommentID: parentCommentID,
            isLiked: isLiked,
            likeCount: isLiked ? 4 : 3
        )
    }
}

@MainActor
private final class PostInteractionManagingSpy: PostInteractionManaging {
    private(set) var optimisticLikeCallCount = 0
    private(set) var optimisticSaveCallCount = 0
    private(set) var restoreLikeCallCount = 0
    private(set) var restoreSaveCallCount = 0

    func state(for postID: PostID) -> LookbookPostInteractionState? {
        nil
    }

    func postStateInvalidationStream(
        for postIDs: Set<PostID>
    ) -> AsyncStream<PostID> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func pinScope(
        postIDs: Set<PostID>,
        commentIDs: Set<CommentID>
    ) -> InteractionPinScope {
        InteractionPinScope {}
    }

    func seed(
        post: LookbookPost,
        visibleCommentCount: Int?,
        userState: PostUserState?
    ) {}

    func seedPostMetrics(_ post: LookbookPost) {}

    func applyOptimisticLike(
        postID: PostID,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool?,
        baseLikeCount: Int?
    ) {
        optimisticLikeCallCount += 1
    }

    func applyOptimisticSave(
        postID: PostID,
        userID: UserID,
        isSaved: Bool,
        baseSaved: Bool?,
        baseSaveCount: Int?
    ) {
        optimisticSaveCallCount += 1
    }

    func applyLikeResult(
        _ result: PostEngagementResult,
        shouldApplySave: Bool
    ) {}

    func applySaveResult(
        _ result: PostEngagementResult,
        shouldApplyLike: Bool
    ) {}

    func restoreLike(
        postID: PostID,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    ) {
        restoreLikeCallCount += 1
    }

    func restoreSave(
        postID: PostID,
        userID: UserID,
        isSaved: Bool,
        saveCount: Int?
    ) {
        restoreSaveCallCount += 1
    }
}

@MainActor
private final class CommentInteractionManagingSpy: CommentInteractionManaging {
    private(set) var optimisticLikeCallCount = 0
    private(set) var restoreLikeCallCount = 0
    private(set) var representativeCommentInvalidationPostIDs: [PostID] = []

    func replyCount(for comment: OutPick.Comment) -> Int {
        comment.replyCount
    }

    func likeCount(for comment: OutPick.Comment) -> Int {
        comment.likeCount
    }

    func isCommentLiked(_ comment: OutPick.Comment, userID: UserID?) -> Bool {
        false
    }

    func isCommentHidden(_ commentID: CommentID) -> Bool {
        false
    }

    func commentState(for commentID: CommentID) -> CommentInteractionState? {
        nil
    }

    func commentStateInvalidationStream(for commentIDs: Set<CommentID>) -> AsyncStream<CommentID> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func representativeCommentInvalidationStream(for postID: PostID) -> AsyncStream<PostID> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func pinScope(
        postIDs: Set<PostID>,
        commentIDs: Set<CommentID>
    ) -> InteractionPinScope {
        InteractionPinScope {}
    }

    func hideCommentIDs(_ commentIDs: Set<CommentID>) {}

    func invalidateRepresentativeComment(for postID: PostID) {
        representativeCommentInvalidationPostIDs.append(postID)
    }

    func seedCommentLikeStates(
        comments: [OutPick.Comment],
        userStates: [CommentID: CommentUserState],
        userID: UserID
    ) {}

    func applyOptimisticCommentLike(
        comment: OutPick.Comment,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool?,
        baseLikeCount: Int?
    ) {
        optimisticLikeCallCount += 1
    }

    func applyCommentLikeResult(_ result: CommentEngagementResult) {}

    func restoreCommentLike(
        comment: OutPick.Comment,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int
    ) {
        restoreLikeCallCount += 1
    }

    func applyCommentMutation(_ result: CommentMutationResult) {}

    func applyCommentDeletion(_ result: CommentDeletionResult) {}
}
