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

@MainActor
final class PostCommentCoordinator: ObservableObject {
    @Published private(set) var isCommentSheetPresented: Bool = false
    @Published private(set) var replyRoute: PostCommentReplyRoute?

    func presentComments() {
        isCommentSheetPresented = true
    }

    func dismissComments() {
        isCommentSheetPresented = false
        replyRoute = nil
    }

    func presentReplies(for parentComment: Comment) {
        replyRoute = PostCommentReplyRoute(parentComment: parentComment)
    }

    func dismissReplies() {
        replyRoute = nil
    }
}
