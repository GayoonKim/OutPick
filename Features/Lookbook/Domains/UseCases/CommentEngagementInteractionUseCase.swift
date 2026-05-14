//
//  CommentEngagementInteractionUseCase.swift
//  OutPick
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct CommentEngagementInteractionInput {
    let brandID: BrandID
    let seasonID: SeasonID
    let postID: PostID
    let comment: Comment
    let userID: UserID
    let currentLiked: Bool
    let currentLikeCount: Int
}

struct CommentEngagementInteractionOutcome {
    let errorMessage: String?
}

@MainActor
final class CommentEngagementInteractionUseCase {
    private let repository: any CommentEngagementRepositoryProtocol
    private let commentInteractionStore: any CommentInteractionManaging
    private let debugFailureInjectionStore: LookbookDebugFailureInjectionStore?

    private var mutatingCommentIDs: Set<CommentID> = []

    init(
        repository: any CommentEngagementRepositoryProtocol,
        commentInteractionStore: any CommentInteractionManaging,
        debugFailureInjectionStore: LookbookDebugFailureInjectionStore? = nil
    ) {
        self.repository = repository
        self.commentInteractionStore = commentInteractionStore
        self.debugFailureInjectionStore = debugFailureInjectionStore
    }

    func toggleLike(
        input: CommentEngagementInteractionInput,
        onMutationStateChanged: (CommentID, Bool) -> Void
    ) async -> CommentEngagementInteractionOutcome {
        let commentID = input.comment.id
        guard mutatingCommentIDs.contains(commentID) == false else {
            return CommentEngagementInteractionOutcome(errorMessage: nil)
        }

        let targetLiked = !input.currentLiked
        mutatingCommentIDs.insert(commentID)
        onMutationStateChanged(commentID, true)
        commentInteractionStore.applyOptimisticCommentLike(
            comment: input.comment,
            userID: input.userID,
            isLiked: targetLiked,
            baseLiked: input.currentLiked,
            baseLikeCount: input.currentLikeCount
        )
        defer {
            mutatingCommentIDs.remove(commentID)
            onMutationStateChanged(commentID, false)
        }

        do {
            try debugFailureInjectionStore?.throwIfNeeded(.toggleCommentLike)
            let result = try await repository.setLike(
                brandID: input.brandID,
                seasonID: input.seasonID,
                postID: input.postID,
                commentID: commentID,
                isLiked: targetLiked
            )
            commentInteractionStore.applyCommentLikeResult(result)
            return CommentEngagementInteractionOutcome(errorMessage: nil)
        } catch {
            commentInteractionStore.restoreCommentLike(
                comment: input.comment,
                userID: input.userID,
                isLiked: input.currentLiked,
                likeCount: input.currentLikeCount
            )
            return CommentEngagementInteractionOutcome(
                errorMessage: "좋아요를 반영하지 못했어요."
            )
        }
    }
}
