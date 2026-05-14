//
//  CommentUserStateRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/14/26.
//

import Foundation

protocol CommentUserStateRepositoryProtocol {
    func fetchCommentUserStates(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentIDs: [CommentID]
    ) async throws -> [CommentID: CommentUserState]
}
