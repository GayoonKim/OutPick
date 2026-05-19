//
//  PostCommentCoordinator.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import Foundation

struct PostCommentReplyRoute: Identifiable, Equatable {
    let parentComment: Comment

    var id: CommentID {
        parentComment.id
    }
}

struct PostCommentProfileRoute: Identifiable, Equatable {
    let author: CommentAuthorDisplay

    var id: UserID {
        author.userID
    }
}

@MainActor
final class PostCommentCoordinator: ObservableObject {
    @Published private(set) var isCommentSheetPresented: Bool = false
    @Published private(set) var replyRoute: PostCommentReplyRoute?
    @Published private(set) var profileRoute: PostCommentProfileRoute?

    func presentComments() {
        isCommentSheetPresented = true
    }

    func dismissComments() {
        isCommentSheetPresented = false
        replyRoute = nil
        profileRoute = nil
    }

    func presentReplies(for parentComment: Comment) {
        replyRoute = PostCommentReplyRoute(parentComment: parentComment)
    }

    func dismissReplies() {
        replyRoute = nil
    }

    func presentProfile(for author: CommentAuthorDisplay) {
        profileRoute = PostCommentProfileRoute(author: author)
    }

    func dismissProfile() {
        profileRoute = nil
    }
}
