//
//  LookbookInteractionStoreTests.swift
//  OutPickTests
//
//  Created by Codex on 5/12/26.
//

import Foundation
import Testing
@testable import OutPick

struct LookbookInteractionStoreTests {
    @Test func pinAwareCacheEvictsUnpinnedLRUButKeepsPinnedEntry() {
        let now = Date()
        var cache = PinAwareInteractionCache<String, Int>(
            maxCount: 2,
            retentionInterval: 60
        )

        cache.set(1, for: "pinned", now: now)
        cache.set(2, for: "old", now: now.addingTimeInterval(1))
        cache.pin(["pinned"], now: now.addingTimeInterval(2))
        cache.set(3, for: "new", now: now.addingTimeInterval(3))

        #expect(cache.value(for: "pinned", now: now.addingTimeInterval(4)) == 1)
        #expect(cache.value(for: "old", now: now.addingTimeInterval(4)) == nil)
        #expect(cache.value(for: "new", now: now.addingTimeInterval(4)) == 3)
    }

    @Test func pinAwareCacheRequiresAllPinScopesToReleaseBeforeEviction() {
        let now = Date()
        var cache = PinAwareInteractionCache<String, Int>(
            maxCount: 1,
            retentionInterval: 60
        )

        cache.set(1, for: "comment", now: now)
        cache.pin(["comment"], now: now.addingTimeInterval(1))
        cache.pin(["comment"], now: now.addingTimeInterval(2))
        cache.set(2, for: "other", now: now.addingTimeInterval(3))

        #expect(cache.value(for: "comment", now: now.addingTimeInterval(4)) == 1)
        #expect(cache.value(for: "other", now: now.addingTimeInterval(4)) == nil)

        cache.unpin(["comment"], now: now.addingTimeInterval(5))
        cache.set(2, for: "other", now: now.addingTimeInterval(6))

        #expect(cache.value(for: "comment", now: now.addingTimeInterval(7)) == 1)
        #expect(cache.value(for: "other", now: now.addingTimeInterval(7)) == nil)

        cache.unpin(["comment"], now: now.addingTimeInterval(8))
        cache.set(2, for: "other", now: now.addingTimeInterval(9))

        #expect(cache.value(for: "comment", now: now.addingTimeInterval(10)) == nil)
        #expect(cache.value(for: "other", now: now.addingTimeInterval(10)) == 2)
    }

    @Test func commentStoreKeepsHiddenStateWhenReplyCountChanges() {
        let commentID = CommentID(value: "comment-1")
        var store = CommentInteractionStore(
            maxCommentStateCount: 10,
            stateRetentionInterval: 60
        )

        store.hide(commentID)
        store.applyReplyCount(3, for: commentID)

        let state = store.state(for: commentID)
        #expect(state?.isHidden == true)
        #expect(state?.replyCount == 3)
    }

    @MainActor
    @Test func commentStateInvalidationStreamPublishesOnlyRequestedComment() async throws {
        let hiddenCommentID = CommentID(value: "hidden-comment")
        let untouchedCommentID = CommentID(value: "untouched-comment")
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            stateRetentionInterval: 60
        )
        var hiddenEvents: [CommentID] = []
        var untouchedEvents: [CommentID] = []

        let hiddenTask = Task { @MainActor in
            for await commentID in store.commentStateInvalidationStream(for: [hiddenCommentID]) {
                hiddenEvents.append(commentID)
                break
            }
        }

        let untouchedTask = Task { @MainActor in
            for await commentID in store.commentStateInvalidationStream(for: [untouchedCommentID]) {
                untouchedEvents.append(commentID)
                break
            }
        }

        await Task.yield()
        store.hideCommentIDs([hiddenCommentID])

        try await waitUntil {
            hiddenEvents == [hiddenCommentID]
        }
        #expect(store.commentState(for: hiddenCommentID)?.isHidden == true)
        #expect(untouchedEvents.isEmpty)
        hiddenTask.cancel()
        untouchedTask.cancel()
    }

    @MainActor
    @Test func commentLikeStateSeedsOptimisticResultAndRestore() {
        let userID = UserID(value: "user-1")
        let comment = makeComment(
            id: CommentID(value: "comment-1"),
            likeCount: 3
        )
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            stateRetentionInterval: 60
        )

        store.seedCommentLikeStates(
            comments: [comment],
            userStates: [
                comment.id: CommentUserState(
                    commentID: comment.id,
                    userID: userID,
                    isLiked: false,
                    updatedAt: Date()
                )
            ],
            userID: userID
        )

        #expect(store.likeCount(for: comment) == 3)
        #expect(store.isCommentLiked(comment, userID: userID) == false)

        store.applyOptimisticCommentLike(
            comment: comment,
            userID: userID,
            isLiked: true,
            baseLiked: false,
            baseLikeCount: 3
        )

        #expect(store.likeCount(for: comment) == 4)
        #expect(store.isCommentLiked(comment, userID: userID) == true)

        store.applyCommentLikeResult(
            CommentEngagementResult(
                brandID: BrandID(value: "brand-1"),
                seasonID: SeasonID(value: "season-1"),
                postID: comment.postID,
                commentID: comment.id,
                userID: userID,
                parentCommentID: nil,
                isLiked: true,
                likeCount: 5
            )
        )

        #expect(store.likeCount(for: comment) == 5)
        #expect(store.isCommentLiked(comment, userID: userID) == true)

        store.restoreCommentLike(
            comment: comment,
            userID: userID,
            isLiked: false,
            likeCount: 3
        )

        #expect(store.likeCount(for: comment) == 3)
        #expect(store.isCommentLiked(comment, userID: userID) == false)
    }

    @MainActor
    @Test func postStateInvalidationStreamPublishesOnlyRequestedPost() async throws {
        let includedPostID = PostID(value: "included-post")
        let outsidePostID = PostID(value: "outside-post")
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            stateRetentionInterval: 60
        )
        var receivedPostIDs: [PostID] = []

        let task = Task { @MainActor in
            for await postID in store.postStateInvalidationStream(for: [includedPostID]) {
                receivedPostIDs.append(postID)
                break
            }
        }

        await Task.yield()
        store.seedPostMetrics(makePost(id: outsidePostID, commentCount: 10))

        #expect(receivedPostIDs.isEmpty)

        store.seedPostMetrics(makePost(id: includedPostID, commentCount: 2))

        try await waitUntil {
            receivedPostIDs == [includedPostID]
        }
        #expect(store.state(for: includedPostID)?.metrics.commentCount == 2)
        task.cancel()
    }

    @MainActor
    @Test func representativeCommentInvalidationStreamPublishesOnlyRequestedPost() async throws {
        let targetPostID = PostID(value: "target-post")
        let otherPostID = PostID(value: "other-post")
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            stateRetentionInterval: 60
        )
        var receivedPostIDs: [PostID] = []

        let task = Task { @MainActor in
            for await postID in store.representativeCommentInvalidationStream(for: targetPostID) {
                receivedPostIDs.append(postID)
                break
            }
        }

        await Task.yield()
        store.invalidateRepresentativeComment(for: otherPostID)
        #expect(receivedPostIDs.isEmpty)

        store.invalidateRepresentativeComment(for: targetPostID)
        try await waitUntil {
            receivedPostIDs == [targetPostID]
        }
        task.cancel()
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while predicate() == false && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(predicate())
    }

    private func makePost(
        id: PostID,
        commentCount: Int
    ) -> LookbookPost {
        LookbookPost(
            id: id,
            brandID: BrandID(value: "brand-1"),
            seasonID: SeasonID(value: "season-1"),
            authorID: UserID(value: "author-1"),
            media: [
                MediaAsset(
                    type: .image,
                    remoteURL: URL(string: "https://example.com/post.jpg")!,
                    thumbPath: nil,
                    detailPath: nil,
                    sourcePageURL: nil
                )
            ],
            caption: nil,
            tagIDs: [],
            metrics: PostMetrics(
                likeCount: 0,
                commentCount: commentCount,
                replacementCount: 0,
                saveCount: 0,
                viewCount: nil
            ),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeComment(
        id: CommentID,
        likeCount: Int
    ) -> OutPick.Comment {
        OutPick.Comment(
            id: id,
            postID: PostID(value: "post-1"),
            userID: UserID(value: "author-1"),
            message: "댓글",
            createdAt: Date(),
            isDeleted: false,
            likeCount: likeCount,
            replyCount: 0,
            isPinned: false,
            pinnedAt: nil,
            pinnedBy: nil,
            parentCommentID: nil,
            attachments: []
        )
    }
}
